#!/usr/bin/env python3
"""Verify exact official library/config bytes in a built desktop distribution ZIP."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('platform', choices=['macos', 'windows'])
parser.add_argument('archive', type=Path)
args = parser.parse_args()
manifest = json.loads((ROOT / 'native/official/manifest.json').read_text())

with zipfile.ZipFile(args.archive) as archive:
    paths = archive.namelist()
    if len(paths) != len(set(paths)):
        raise SystemExit('Duplicate archive entries are ambiguous')
    for item in manifest['files']:
        if item['platform'] != args.platform:
            continue
        filename = Path(item['path']).name
        if args.platform == 'macos':
            directory = 'Resources' if item.get('kind') == 'config' else 'Frameworks'
            member = f'UURemoteClone.app/Contents/{directory}/{filename}'
        else:
            member = filename
        data = archive.read(member)
        if len(data) != item['bytes'] or hashlib.sha256(data).hexdigest() != item['sha256']:
            raise SystemExit('Packaged installer member identity mismatch: ' + member)
        print('PASS packaged original library/config: ' + member)
    if args.platform == 'macos':
        executable = archive.getinfo('UURemoteClone.app/Contents/MacOS/UURemoteClone')
        if not ((executable.external_attr >> 16) & 0o111):
            raise SystemExit('macOS executable permissions were lost in packaging')
    else:
        for member in ('UURemoteClone.exe', 'gvpb.dll'):
            if archive.read(member)[:2] != b'MZ':
                raise SystemExit('Missing/invalid Windows binary in distribution: ' + member)
print('Static distribution identity check only; not an application launch or interoperability test.')
