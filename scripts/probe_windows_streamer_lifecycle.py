#!/usr/bin/env python3
"""CI-only, isolated Initialize/Finalize probes of the supplied Windows DLL.

Windows slot 0's three pointers reach UTF-16 consumers, despite byte-oriented
length scans in its outer wrapper. Slots/callback lengths are artifact-specific.
No room, connection, capture, codec-capability query or media call is made.
"""
import argparse
import ctypes
import json
import os
from pathlib import Path
import platform
import shutil
import sys
import traceback

from probe_windows_codec_detector import ROOT, digest, observe


def save(path, report):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    temporary.replace(path)


def collect_workspace(workspace):
    files = []
    for path in sorted(workspace.rglob('*')):
        if not path.is_file():
            continue
        data = path.read_bytes()
        item = {'path': str(path.relative_to(workspace)), 'bytes': len(data), 'sha256': digest(data)}
        if '.log' in path.name.lower() or path.suffix.lower() in ('.txt', '.slog'):
            item['text_preview'] = data[:256 * 1024].decode('utf-8', errors='replace')
            item['text_preview_truncated'] = len(data) > 256 * 1024
        files.append(item)
    return files


def version(table, role):
    function = ctypes.WINFUNCTYPE(ctypes.c_int, ctypes.POINTER(ctypes.c_void_p),
                                 ctypes.POINTER(ctypes.c_uint32))(table[17 if role == 'controller' else 18])
    pointer, size = ctypes.c_void_p(), ctypes.c_uint32()
    code = function(ctypes.byref(pointer), ctypes.byref(size))
    if code != 0 or not pointer.value or not 0 < size.value <= 4096:
        raise RuntimeError(f'Version result invalid: code={code}, size={size.value}')
    return {'status': code, 'value': ctypes.string_at(pointer, size.value).decode('utf-8')}


def child(runtime, workspace, role, output):
    manifest = json.loads((ROOT / 'native/official/manifest.json').read_text())
    for item in manifest['files']:
        if item['platform'] == 'windows':
            data = (runtime / Path(item['path']).name).read_bytes()
            if digest(data) != item['sha256'] or len(data) != item['bytes']:
                raise RuntimeError('Original runtime identity mismatch')
    workspace.mkdir(parents=True, exist_ok=False)
    log_directory = workspace / 'logs'
    log_directory.mkdir()
    # A non-ASCII config path distinguishes UTF-16 from a guessed UTF-8 API.
    config = workspace / 'config-配置.json'
    shutil.copyfile(runtime / 'streamer-config.json', config)
    inputs = [str(log_directory), str(config), 'ci-' + role]
    report = {'role': role, 'phase': 'loading', 'passed': False,
              'library_sha256': digest((runtime / 'streamer.dll').read_bytes()),
              'config_sha256': digest(config.read_bytes()),
              'slot_0_inputs': inputs, 'string_encoding': 'UTF-16LE, NUL-terminated'}
    save(output, report)
    os.chdir(workspace)
    # Keep the module, pointer table, callbacks and path buffers alive until the
    # child exits. Never unload a DLL whose global thread cleanup is uncertain.
    module = ctypes.WinDLL(str(runtime / 'streamer.dll'), winmode=0x100 | 0x1000)
    factory = getattr(module, 'ExchangeControllerInterface' if role == 'controller' else 'ExchangeControlledInterface')
    factory.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
    factory.restype = ctypes.POINTER(ctypes.c_void_p)
    callbacks = (ctypes.c_void_p * (18 if role == 'controller' else 16))()
    table = factory(callbacks)
    if not table:
        raise RuntimeError('Factory returned a null table')
    initialize = ctypes.WINFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)(table[0])
    finalize = ctypes.WINFUNCTYPE(ctypes.c_int)(table[1])
    buffers = [ctypes.create_unicode_buffer(value) for value in inputs]
    if ctypes.sizeof(ctypes.c_wchar) != 2:
        raise RuntimeError('Windows UTF-16 wchar ABI is required')
    try:
        report['version_before'] = version(table, role)
        report['phase'] = 'initialize'
        save(output, report)
        report['initialize_status'] = initialize(*(ctypes.cast(buffer, ctypes.c_void_p) for buffer in buffers))
        report['phase'] = 'finalize'
        save(output, report)
        report['finalize_status'] = finalize()
        report['version_after'] = version(table, role)
        report['phase'] = 'complete'
    except BaseException:
        report['error'] = traceback.format_exc()
    report['workspace_files'] = collect_workspace(workspace)
    report['config_open_failure_seen'] = any('failed to open json config' in item.get('text_preview', '')
                                            for item in report['workspace_files'])
    report['passed'] = (report.get('initialize_status') == 0 and report.get('finalize_status') == 0
                        and report['phase'] == 'complete' and not report['config_open_failure_seen']
                        and report['version_before']['value'] == manifest['streamer_version']
                        and report['version_after']['value'] == manifest['streamer_version'])
    save(output, report)
    return 0 if report['passed'] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--child', choices=['controller', 'controlled'])
    parser.add_argument('--debugger', type=Path, help='Runner-built native failure observer; invoked only after failure')
    args = parser.parse_args()
    if platform.system() != 'Windows' or os.environ.get('GITHUB_ACTIONS') != 'true':
        parser.error('Original target execution is restricted to Windows GitHub Actions')
    runtime, workspace, output = args.runtime.resolve(), args.workspace.resolve(), args.output.resolve()
    if args.child:
        return child(runtime, workspace, args.child, output)
    cases = []
    for role in ('controller', 'controlled'):
        child_output = output.with_name('lifecycle-' + role + '.json')
        def command_for(case_workspace, case_output):
            return [sys.executable, str(Path(__file__).resolve()), '--runtime', str(runtime),
                    '--workspace', str(case_workspace), '--output', str(case_output), '--child', role]

        observation = observe(command_for(workspace / role, child_output), runtime, timeout=60)
        child_report = json.loads(child_output.read_text(encoding='utf-8')) if child_output.exists() else None
        case = {'role': role, 'process': observation, 'native': child_report,
                'workspace_files_after_exit': collect_workspace(workspace / role),
                'passed': observation['exit_code'] == 0 and not observation['timed_out']
                          and child_report is not None and child_report.get('passed', False)}
        if not case['passed'] and args.debugger:
            debug_workspace = workspace / (role + '-debug')
            debug_output = output.with_name('lifecycle-' + role + '-debug.json')
            events = output.with_name('lifecycle-' + role + '-debugger.jsonl')
            debug_command = [str(args.debugger.resolve()), str(events), *command_for(debug_workspace, debug_output)]
            try:
                debug_process = observe(debug_command, runtime, timeout=120)
            except OSError as error:
                case['debug_retry'] = {'launch_error': str(error)}
            else:
                case['debug_retry'] = {
                    'process': debug_process,
                    'native': json.loads(debug_output.read_text(encoding='utf-8')) if debug_output.exists() else None,
                    'events': [json.loads(line) for line in events.read_text(encoding='utf-8').splitlines()] if events.exists() else [],
                    'workspace_files_after_exit': collect_workspace(debug_workspace),
                    'scope': 'Debugger-attached diagnostic retry; does not replace the failed ordinary observation.'}
        cases.append(case)
    report = {'source_commit': os.environ.get('GITHUB_SHA'), 'run_id': os.environ.get('GITHUB_RUN_ID'),
              'platform': platform.platform(), 'observations': cases,
              'passed': all(case['passed'] for case in cases),
              'scope': 'Isolated original DLL factory/version/Initialize/Finalize calls only.',
              'limitations': ['No room, signaling, capture, codecs, input or media session is executed.',
                              'Native callbacks are null; callback signatures and delivery remain untested.',
                              'A zero Initialize result alone does not prove config consumption or hardware success.',
                              'The third UTF-16 string is a log filename suffix; complete logging semantics remain under analysis.']}
    save(output, report)
    for case in cases:
        native = case['native'] or {}
        print(json.dumps({'role': case['role'], 'passed': case['passed'], 'phase': native.get('phase'),
                          'initialize_status': native.get('initialize_status'),
                          'finalize_status': native.get('finalize_status'),
                          'exit_code': case['process']['exit_code'], 'timed_out': case['process']['timed_out']}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
