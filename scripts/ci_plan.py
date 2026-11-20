#!/usr/bin/env python3
"""Select affected CI jobs; does not compile applications or contact services itself."""
import argparse
import json
import os
from pathlib import Path
import subprocess

TARGETS = ('core', 'macos', 'windows', 'android')


def affected(paths):
    selected = set()
    for path in paths:
        if path in ('.github/workflows/build.yml', '.gitattributes'):
            selected.update(TARGETS)
        elif path.startswith(('core/', 'proto/', 'native/official/include/')) or path == 'native/official/official_streamer_abi.cpp':
            selected.update(TARGETS)
        elif path in ('native/official/manifest.json', 'native/official/runtime-chunks/index.json'):
            selected.update(('macos', 'windows', 'android'))
        elif path.startswith(('Sources/', 'Tests/OfficialStreamerTests/', 'native/official/runtime/macos/',
                              'native/official/runtime-chunks/macos/')) or path in ('Package.swift', 'Package.resolved', 'scripts/make_app.sh'):
            selected.add('macos')
        elif path.startswith(('platforms/windows/', 'Tests/WindowsOfficialSmoke/', 'Tests/WindowsPeerSmoke/',
                              'native/official/runtime/windows/', 'native/official/runtime-chunks/windows/')):
            selected.add('windows')
        elif path.startswith('platforms/android/') or path in ('scripts/verify_android_abi.py', 'scripts/verify_android_package.py'):
            selected.add('android')
        elif path in ('scripts/restore_official_runtime.py', 'scripts/verify_official_runtime.py', 'scripts/verify_desktop_package.py'):
            selected.update(('macos', 'windows'))
    return {target: target in selected for target in TARGETS}


def plan(event, event_name, get_changed):
    if event_name == 'workflow_dispatch':
        target = event.get('inputs', {}).get('target', 'all')
        if target not in (*TARGETS, 'all'):
            raise ValueError('Unknown requested target: ' + target)
        return {name: target in (name, 'all') for name in TARGETS}, []
    before, after = event.get('before', ''), event['after']
    if not before or set(before) == {'0'}:
        return {name: True for name in TARGETS}, ['(new branch: validate all targets)']
    paths = get_changed(before, after)
    return affected(paths), paths


def changed_files(before, after):
    for sha in (before, after):
        if subprocess.run(['git', 'cat-file', '-e', sha + '^{commit}'], capture_output=True).returncode:
            subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', sha], check=True)
    # --no-renames includes both sides of renames so moving code between platforms
    # cannot silently skip validation of the removed implementation.
    output = subprocess.check_output(['git', 'diff', '--no-renames', '--name-only', '-z', before, after])
    return [name.decode() for name in output.split(b'\0') if name]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--event', type=Path, required=True)
    parser.add_argument('--event-name', default=os.environ.get('GITHUB_EVENT_NAME', 'push'))
    args = parser.parse_args()
    selected, paths = plan(json.loads(args.event.read_text()), args.event_name, changed_files)
    output = '\n'.join(f'{name}={str(enabled).lower()}' for name, enabled in selected.items()) + '\n'
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
            stream.write(output)
    print(output, end='')
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as stream:
            stream.write('### Selected builds\n\n')
            stream.write(', '.join(name for name, enabled in selected.items() if enabled) or 'Static checks only')
            stream.write('\n\nSelected from the changed paths (or explicit manual target).\n')
    print(json.dumps({'changed_paths': paths, 'selected': selected}))


if __name__ == '__main__':
    main()
