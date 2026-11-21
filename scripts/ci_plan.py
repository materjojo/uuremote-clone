#!/usr/bin/env python3
"""Select affected CI jobs; does not compile applications or contact services itself."""
import argparse
import json
import os
import re
from pathlib import Path
import subprocess

TARGETS = ('core', 'macos', 'windows', 'android')
WORKFLOW_JOBS = {'plan': set(TARGETS), 'core': {'core'}, 'macos-app': {'macos'},
                 'windows-app': {'windows'}, 'android-app': {'android'}}


def runtime_groups(text, path):
    """Separate shared metadata from each platform's original runtime records."""
    document = json.loads(text)
    records = document.pop('files')
    groups = {name: [] for name in ('macos', 'windows', 'android')}
    for record in records:
        platform = record.get('platform')
        if path.endswith('runtime-chunks/index.json'):
            platform = record['output'].split('/')[3]
        if platform not in groups:
            raise ValueError('Unknown runtime platform')
        groups[platform].append(record)
    return document, groups


def workflow_groups(text):
    """Read only top-level job blocks; unknown layouts fall back to all targets."""
    header, marker, jobs = text.partition('\njobs:\n')
    if not marker or re.search(r'^[^\s#]', jobs, re.MULTILINE):
        raise ValueError('Unrecognized workflow layout')
    matches = list(re.finditer(r'^  ([a-zA-Z0-9_-]+):\s*$', jobs, re.MULTILINE))
    if not matches or jobs[:matches[0].start()].strip():
        raise ValueError('Unrecognized workflow jobs')
    groups = {}
    for index, match in enumerate(matches):
        name = match.group(1)
        if name not in WORKFLOW_JOBS or name in groups:
            raise ValueError('Unknown or duplicate workflow job')
        end = matches[index + 1].start() if index + 1 < len(matches) else len(jobs)
        groups[name] = jobs[match.start():end]
    return header, groups


def shared_file_targets(path, before, after):
    """Conservatively narrow shared files using both committed revisions."""
    try:
        if path == '.github/workflows/build.yml':
            old_header, old = workflow_groups(before)
            new_header, new = workflow_groups(after)
            if old_header != new_header:
                return set(TARGETS)
            return set().union(*(WORKFLOW_JOBS[name] for name in old.keys() | new.keys()
                                 if old.get(name) != new.get(name)))
        old_header, old = runtime_groups(before, path)
        new_header, new = runtime_groups(after, path)
        if old_header != new_header:
            return {'macos', 'windows', 'android'}
        return {name for name in old if old[name] != new[name]}
    except (ValueError, KeyError, TypeError, IndexError):
        return set(TARGETS) if path.endswith('build.yml') else {'macos', 'windows', 'android'}


def affected(paths, read_versions=None):
    selected = set()
    for path in paths:
        if path in ('.github/workflows/build.yml', 'native/official/manifest.json',
                    'native/official/runtime-chunks/index.json') and read_versions is not None:
            selected.update(shared_file_targets(path, *read_versions(path)))
        elif path in ('.github/workflows/build.yml', '.gitattributes'):
            selected.update(TARGETS)
        elif path.startswith(('core/', 'proto/', 'native/official/include/')) or path == 'native/official/official_streamer_abi.cpp':
            selected.update(TARGETS)
        elif path in ('native/official/manifest.json', 'native/official/runtime-chunks/index.json'):
            selected.update(('macos', 'windows', 'android'))
        elif path.startswith(('Sources/', 'Tests/OfficialStreamerTests/', 'native/official/runtime/macos/',
                              'native/official/runtime-chunks/macos/')) or path in ('Package.swift', 'Package.resolved', 'scripts/make_app.sh'):
            selected.add('macos')
        elif path.startswith(('platforms/windows/', 'Tests/WindowsOfficialSmoke/', 'Tests/WindowsPeerSmoke/',
                              'Tests/WindowsCodecDetector/',
                              'native/official/runtime/windows/', 'native/official/runtime-chunks/windows/')):
            selected.add('windows')
        elif path.startswith('platforms/android/') or path in ('scripts/verify_android_abi.py', 'scripts/verify_android_package.py'):
            selected.add('android')
        elif path in ('scripts/probe_windows_codec_detector.py', 'scripts/test_windows_codec_detector.py',
                      'scripts/probe_windows_streamer_lifecycle.py'):
            selected.add('windows')
        elif path in ('scripts/restore_official_runtime.py', 'scripts/verify_official_runtime.py', 'scripts/verify_desktop_package.py'):
            selected.update(('macos', 'windows'))
    return {target: target in selected for target in TARGETS}


def plan(event, event_name, get_changed, get_version=None):
    if event_name == 'workflow_dispatch':
        target = event.get('inputs', {}).get('target', 'all')
        if target not in (*TARGETS, 'all'):
            raise ValueError('Unknown requested target: ' + target)
        return {name: target in (name, 'all') for name in TARGETS}, []
    before, after = event.get('before', ''), event['after']
    if not before or set(before) == {'0'}:
        return {name: True for name in TARGETS}, ['(new branch: validate all targets)']
    paths = get_changed(before, after)
    read_versions = (lambda path: (get_version(before, path), get_version(after, path))) if get_version else None
    return affected(paths, read_versions), paths


def committed_file(revision, path):
    result = subprocess.run(['git', 'show', revision + ':' + path], capture_output=True)
    return result.stdout.decode('utf-8') if result.returncode == 0 else ''


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
    selected, paths = plan(json.loads(args.event.read_text()), args.event_name, changed_files, committed_file)
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
