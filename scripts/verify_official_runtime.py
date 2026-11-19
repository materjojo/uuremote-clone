#!/usr/bin/env python3
"""Verify retained installer members and probe the actual desktop media libraries.

Run in GitHub Actions on macOS/Windows, after building the shared bridge there.
No Initialize/CreateRoom/capture calls are made; this is a version/ABI probe only.
"""
import argparse
import ctypes
import hashlib
import json
import platform
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bridge', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'native/official/manifest.json').read_text())
    for item in manifest['files']:
        path = ROOT / item['path']
        if path.stat().st_size != item['bytes'] or sha256(path) != item['sha256']:
            raise SystemExit('Installer member identity mismatch: ' + str(path))
    print(f'PASS: {len(manifest["files"])} retained native/config files match their recorded SHA-256.')
    if args.bridge is None:
        return
    host = {'Darwin': 'macos', 'Windows': 'windows'}.get(platform.system())
    if host is None:
        raise SystemExit('Runtime probe requires macOS/Windows; identity-only verification is available everywhere')
    item = next(x for x in manifest['files'] if x['platform'] == host and 'member' in x)
    library_path = (ROOT / item['path']).resolve()
    bridge_path = args.bridge.resolve()
    bridge = ctypes.CDLL(str(bridge_path))
    bridge.uu_official_open.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_size_t]
    bridge.uu_official_open.restype = ctypes.c_void_p
    bridge.uu_official_version.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t]
    bridge.uu_official_version.restype = ctypes.c_int
    bridge.uu_official_close.argtypes = [ctypes.c_void_p]
    bridge.uu_official_close.restype = None
    bridge.gvpb_schema_message_count.restype = ctypes.c_int
    count = bridge.gvpb_schema_message_count()
    if count != 179:
        raise SystemExit(f'Shared protobuf ABI returned {count}, expected 179')
    error = ctypes.create_string_buffer(1024)
    if bridge.uu_official_open(str(library_path).encode(), 99, error, len(error)):
        raise SystemExit('Invalid role was accepted')
    observations = []
    for role, label in [(0, 'controller'), (1, 'controlled')]:
        handle = bridge.uu_official_open(str(library_path).encode(), role, error, len(error))
        if not handle:
            raise SystemExit(error.value.decode(errors='replace'))
        try:
            small = ctypes.create_string_buffer(1)
            if bridge.uu_official_version(handle, small, len(small)) != -4:
                raise SystemExit('Version copy did not enforce output capacity')
            version = ctypes.create_string_buffer(4097)
            code = bridge.uu_official_version(handle, version, len(version))
            if code != 0:
                raise SystemExit(f'{label}: native version query failed: {code}')
            value = version.value.decode('utf-8')
            if value != manifest['streamer_version']:
                raise SystemExit(f'{label}: observed {value!r}, expected {manifest["streamer_version"]!r}')
            observations.append({'role': label, 'version': value, 'native_return': code})
            print(f'PASS: actual supplied {host} {label} library returned {value}')
        finally:
            bridge.uu_official_close(handle)
    report = {
        'platform': platform.system(), 'machine': platform.machine(),
        'library_sha256': item['sha256'], 'bridge_sha256': sha256(bridge_path),
        'protobuf_schema_messages': count, 'observations': observations,
        'scope': 'factory + bounded version copy only; not media, signaling, UI or interoperability validation',
    }
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
