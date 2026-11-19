#include "official_streamer_abi.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <new>
#include <vector>
#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string>
#elif defined(__APPLE__)
#include <dlfcn.h>
#endif

struct uu_official_library {
    void *module;
    const void *const *table;
    int version_slot;
};

static void report(char *error, size_t capacity, const char *message) {
    if (error && capacity) std::snprintf(error, capacity, "%s", message);
}

uu_official_library *uu_official_open(const char *path, int role, char *error, size_t capacity) {
    report(error, capacity, "");
    if (!path || !*path || (role != UU_CONTROLLER && role != UU_CONTROLLED)) {
        report(error, capacity, "Invalid library path or role");
        return nullptr;
    }
#if defined(_WIN32) || defined(__APPLE__)
    void *module = nullptr;
    void *symbol = nullptr;
    const char *name = role == UU_CONTROLLER ? "ExchangeControllerInterface" : "ExchangeControlledInterface";
#if defined(_WIN32)
    // Never use ordinal #1 (Intel IGCL). Supplied DLL export ordinals are 3/2.
    const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, nullptr, 0);
    if (!count) { report(error, capacity, "Invalid UTF-8 path"); return nullptr; }
    std::wstring wide(static_cast<size_t>(count), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide.data(), count);
    module = LoadLibraryExW(wide.c_str(), nullptr,
        LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    if (!module) {
        char message[128];
        std::snprintf(message, sizeof(message), "LoadLibraryExW failed: %lu", GetLastError());
        report(error, capacity, message);
        return nullptr;
    }
    symbol = reinterpret_cast<void *>(GetProcAddress(static_cast<HMODULE>(module), name));
    const int callback_count = role == UU_CONTROLLER ? 18 : 16;
#else
    if (path[0] != '/') { report(error, capacity, "An absolute path is required"); return nullptr; }
    module = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!module) { report(error, capacity, dlerror()); return nullptr; }
    symbol = dlsym(module, name);
    const int callback_count = role == UU_CONTROLLER ? 17 : 15;
#endif
    if (!symbol) {
        report(error, capacity, "Required Exchange*Interface export missing");
#if defined(_WIN32)
        FreeLibrary(static_cast<HMODULE>(module));
#else
        dlclose(module);
#endif
        return nullptr;
    }
    // Both x86_64 and ARM64 factory helpers read members through their first
    // pointer argument. This is a C function table, NOT a C++ object/vtable.
    using Factory = const void *const *(*)(const void *);
    std::vector<void *> callbacks(static_cast<size_t>(callback_count), nullptr);
    const auto table = reinterpret_cast<Factory>(symbol)(callbacks.data());
    auto *result = new (std::nothrow) uu_official_library{module, table,
        role == UU_CONTROLLER ? 17 : 18};
    if (!result || !table) {
        delete result;
        report(error, capacity, "Factory did not return a function table");
#if defined(_WIN32)
        FreeLibrary(static_cast<HMODULE>(module));
#else
        dlclose(module);
#endif
        return nullptr;
    }
    return result;
#else
    report(error, capacity, "Official desktop runtime requires macOS or Windows");
    return nullptr;
#endif
}

int uu_official_version(uu_official_library *library, char *output, size_t capacity) {
    if (!library || !output || !capacity || !library->table) return -1;
    output[0] = '\0';
    const void *entry = library->table[library->version_slot];
    if (!entry) return -2;
    using GetVersion = int (*)(const char **, uint32_t *);
    const char *bytes = nullptr;
    uint32_t length = 0;
    // The table entry is the function address. There is NO implicit this.
    const int result = reinterpret_cast<GetVersion>(const_cast<void *>(entry))(&bytes, &length);
    if (result) return result;
    if (!bytes || !length || length > 4096) return -3;
    if (static_cast<size_t>(length) >= capacity) return -4;
    std::memcpy(output, bytes, length);
    output[length] = '\0';
    return 0;
}

void uu_official_close(uu_official_library *library) {
    if (!library) return;
#if defined(_WIN32)
    FreeLibrary(static_cast<HMODULE>(library->module));
#elif defined(__APPLE__)
    dlclose(library->module);
#endif
    delete library;
}
