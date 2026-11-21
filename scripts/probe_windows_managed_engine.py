#!/usr/bin/env python3
"""Run the production Windows C# engine binding in separate Actions processes."""
import argparse
import json
import os
from pathlib import Path
import platform
import sys

from probe_windows_codec_detector import observe
from probe_windows_streamer_lifecycle import collect_workspace, save


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--probe', type=Path, required=True)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if platform.system() != 'Windows' or os.environ.get('GITHUB_ACTIONS') != 'true':
        parser.error('Compiled application tests require Windows GitHub Actions')
    probe, runtime, reference, workspace, output = (value.resolve() for value in
        (args.probe, args.runtime, args.reference, args.workspace, args.output))
    cases = []
    for role in ('controller', 'controlled'):
        child_output = output.with_name('streamer-managed-' + role + '.json')
        result = observe(['dotnet', str(probe), '--engine', role, str(runtime), str(workspace / role),
                          str(child_output), str(reference)], runtime, timeout=240)
        native = json.loads(child_output.read_text(encoding='utf-8')) if child_output.exists() else None
        passed = result['exit_code'] == 0 and not result['timed_out'] and native is not None and native.get('passed', False)
        cases.append({'role': role, 'process': result, 'managed': native,
                      'workspace_files': collect_workspace(workspace / role), 'passed': passed})
        print(json.dumps({'role': role, 'passed': passed, 'phase': native.get('phase') if native else None,
                          'exit_code': result['exit_code'], 'timed_out': result['timed_out']}))
    report = {'source_commit': os.environ.get('GITHUB_SHA'), 'run_id': os.environ.get('GITHUB_RUN_ID'),
              'observations': cases, 'passed': all(case['passed'] for case in cases),
              'scope': 'Production C# original engine lifecycle, exclusive ownership and capability binding only.',
              'limitations': ['No room, capture, actual media, callbacks, GPU usage or cross-platform interaction is tested.',
                              'Reported capability bytes are compared with direct original DLL calls on this runner.']}
    save(output, report)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
