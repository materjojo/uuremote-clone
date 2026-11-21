// Runner-only debugger: records exception addresses and module-relative stack
// frames. It never writes process memory, dumps memory or downloads symbols.
#define NOMINMAX
#include <windows.h>
#include <dbghelp.h>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

static std::string utf8(const std::wstring& value) {
    int size = WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    std::string result(size, '\0');
    if (size) WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), &result[0], size, nullptr, nullptr);
    return result;
}
static std::string quoted(const std::string& value) {
    std::ostringstream result;
    result << '"';
    for (unsigned char c : value) {
        if (c == '"' || c == '\\') result << '\\' << c;
        else if (c < 32) result << "\\u00" << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(c);
        else result << c;
    }
    return result.str() + '"';
}
static std::string hex64(DWORD64 value) {
    std::ostringstream result;
    result << "0x" << std::hex << value;
    return result.str();
}
static std::wstring argument(const wchar_t* value) {
    // CommandLineToArgvW/CRT quoting, including backslashes before closing quote.
    std::wstring result = L"\"";
    size_t slashes = 0;
    for (const wchar_t* p = value; *p; ++p) {
        if (*p == L'\\') { ++slashes; continue; }
        result.append(*p == L'"' ? slashes * 2 + 1 : slashes, L'\\');
        result.push_back(*p);
        slashes = 0;
    }
    result.append(slashes * 2, L'\\');
    return result + L'"';
}
static std::string module_address(HANDLE process, DWORD64 address) {
    IMAGEHLP_MODULE64 module{};
    module.SizeOfStruct = sizeof(module);
    std::ostringstream out;
    out << "{\"address\":" << quoted(hex64(address));
    if (SymGetModuleInfo64(process, address, &module)) {
        out << ",\"module\":" << quoted(module.ImageName) << ",\"module_base\":" << quoted(hex64(module.BaseOfImage))
            << ",\"rva\":" << quoted(hex64(address - module.BaseOfImage));
    }
    out << '}';
    return out.str();
}
static void exception(std::ofstream& output, HANDLE process, const DEBUG_EVENT& event) {
    const auto& info = event.u.Exception;
    const auto& record = info.ExceptionRecord;
    // Resolve unwind tables from local loaded images only; no symbol server.
    SymSetOptions(SYMOPT_DEFERRED_LOADS | SYMOPT_FAIL_CRITICAL_ERRORS | SYMOPT_NO_PROMPTS | SYMOPT_IGNORE_NT_SYMPATH);
    bool symbols = SymInitialize(process, "", TRUE) != FALSE;
    output << "{\"event\":\"exception\",\"code\":" << quoted(hex64(record.ExceptionCode))
           << ",\"first_chance\":" << (info.dwFirstChance ? "true" : "false")
           << ",\"thread\":" << event.dwThreadId << ",\"location\":"
           << module_address(process, reinterpret_cast<DWORD64>(record.ExceptionAddress));
    output << ",\"parameters\":[";
    for (DWORD i = 0; i < record.NumberParameters && i < EXCEPTION_MAXIMUM_PARAMETERS; ++i) {
        if (i) output << ',';
        output << quoted(hex64(record.ExceptionInformation[i]));
    }
    output << "],\"frames\":[";
    HANDLE thread = OpenThread(THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, event.dwThreadId);
    CONTEXT context{};
    context.ContextFlags = CONTEXT_FULL;
    bool got_context = thread && GetThreadContext(thread, &context);
    if (got_context) {
        output << module_address(process, context.Rip);
        STACKFRAME64 frame{};
        frame.AddrPC.Offset = context.Rip;
        frame.AddrStack.Offset = context.Rsp;
        frame.AddrFrame.Offset = context.Rbp;
        frame.AddrPC.Mode = frame.AddrStack.Mode = frame.AddrFrame.Mode = AddrModeFlat;
        DWORD64 previous = context.Rip;
        for (int i = 0; symbols && i < 48; ++i) {
            if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64, process, thread, &frame, &context, nullptr,
                             SymFunctionTableAccess64, SymGetModuleBase64, nullptr)
                || !frame.AddrPC.Offset) break;
            if (frame.AddrPC.Offset == previous) continue;
            previous = frame.AddrPC.Offset;
            output << ',' << module_address(process, frame.AddrPC.Offset);
        }
    }
    output << "],\"context_available\":" << (got_context ? "true" : "false")
           << ",\"symbol_initialization\":" << (symbols ? "true" : "false") << "}\n" << std::flush;
    if (thread) CloseHandle(thread);
    if (symbols) SymCleanup(process);
}
int wmain(int argc, wchar_t** argv) {
    if (argc < 3) { std::cerr << "usage: native_failure_observer report.jsonl program [arguments...]\n"; return 2; }
    std::ofstream output(std::filesystem::path(argv[1]), std::ios::binary);
    if (!output) return 3;
    std::wstring command;
    for (int i = 2; i < argc; ++i) { if (i > 2) command += L' '; command += argument(argv[i]); }
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(nullptr, &command[0], nullptr, nullptr, TRUE, DEBUG_ONLY_THIS_PROCESS,
                        nullptr, nullptr, &startup, &process)) {
        output << "{\"event\":\"create_failed\",\"error\":" << GetLastError() << "}\n";
        return 4;
    }
    DWORD result = 1;
    ULONGLONG started = GetTickCount64();
    bool initial_breakpoint = true;
    for (;;) {
        DEBUG_EVENT event{};
        if (!WaitForDebugEvent(&event, 1000)) {
            if (GetLastError() != ERROR_SEM_TIMEOUT) break;
            if (GetTickCount64() - started > 90000) {
                output << "{\"event\":\"timeout\"}\n" << std::flush;
                TerminateProcess(process.hProcess, WAIT_TIMEOUT);
                started = GetTickCount64();
            }
            continue;
        }
        DWORD continuation = DBG_CONTINUE;
        bool exited = false;
        if (event.dwDebugEventCode == EXCEPTION_DEBUG_EVENT) {
            DWORD code = event.u.Exception.ExceptionRecord.ExceptionCode;
            if (code == EXCEPTION_BREAKPOINT && initial_breakpoint) initial_breakpoint = false;
            else {
                // C++ first-chance exceptions can be handled normally. Record
                // native memory failures immediately, plus all second chances.
                if (!event.u.Exception.dwFirstChance || code == 0xc0000374 || code == EXCEPTION_ACCESS_VIOLATION
                    || code == 0xc0000409 || code == 0xc000001d) exception(output, process.hProcess, event);
                continuation = DBG_EXCEPTION_NOT_HANDLED;
            }
        } else if (event.dwDebugEventCode == CREATE_PROCESS_DEBUG_EVENT) {
            if (event.u.CreateProcessInfo.hFile) CloseHandle(event.u.CreateProcessInfo.hFile);
        } else if (event.dwDebugEventCode == LOAD_DLL_DEBUG_EVENT) {
            if (event.u.LoadDll.hFile) CloseHandle(event.u.LoadDll.hFile);
        } else if (event.dwDebugEventCode == EXIT_PROCESS_DEBUG_EVENT) {
            result = event.u.ExitProcess.dwExitCode;
            output << "{\"event\":\"exit\",\"code\":" << result << "}\n" << std::flush;
            exited = true;
        }
        if (!ContinueDebugEvent(event.dwProcessId, event.dwThreadId, continuation) || exited) break;
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return static_cast<int>(result);
}
