#!/usr/bin/env python3
"""Check that APK packaging preserves the selected official ARM64 libraries/config."""
import hashlib
import json
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'native/official/manifest.json').read_text())
with zipfile.ZipFile(sys.argv[1]) as apk:
    checked = 0
    for item in manifest['files']:
        if item['platform'] != 'android':
            continue
        member = item.get('member', 'assets/streamer/streamer-config.json')
        data = apk.read(member)
        if len(data) != item['bytes'] or hashlib.sha256(data).hexdigest() != item['sha256']:
            raise SystemExit('Packaging modified the official installer member: ' + member)
        print('PASS original APK member identity: ' + member)
        checked += 1
    if checked != 4:
        raise SystemExit(f'Unexpected native/config check count: {checked}')
    if 'lib/arm64-v8a/libgvpb.so' not in apk.namelist():
        raise SystemExit('Shared protocol core libgvpb.so missing')
print('Static packaging checks only; Android native execution has not been verified.')
