#!/usr/bin/env python3
"""Restore unchanged supplied desktop libraries from bounded, hashed gzip chunks.

Chunking is storage/transport only. Output SHA-256 must match the installer
manifest before any CI loader or packaging command can use it. No compilation.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INDEX = ROOT / 'native/official/runtime-chunks/index.json'
CHUNK_BYTES = 512 * 1024


def digest(data):
    return hashlib.sha256(data).hexdigest()


def pack():
    manifest = json.loads((ROOT / 'native/official/manifest.json').read_text())
    records = []
    for item in manifest['files']:
        if item['platform'] not in ('macos', 'windows') or item.get('kind') == 'config':
            continue
        raw = (ROOT / item['path']).read_bytes()
        if digest(raw) != item['sha256']:
            raise SystemExit('Cannot pack modified installer member: ' + item['path'])
        compressed = gzip.compress(raw, compresslevel=9, mtime=0)
        chunks = []
        for offset in range(0, len(compressed), CHUNK_BYTES):
            data = compressed[offset:offset + CHUNK_BYTES]
            relative = f"{item['platform']}/{Path(item['path']).name}.gz.part{offset // CHUNK_BYTES:03}"
            path = INDEX.parent / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            chunks.append({'path': relative, 'bytes': len(data), 'sha256': digest(data)})
        records.append({'output': item['path'], 'bytes': len(raw), 'sha256': item['sha256'], 'chunks': chunks})
        print(f"Packed {item['platform']}: {len(raw)} bytes -> {len(compressed)} bytes / {len(chunks)} chunks")
    INDEX.write_text(json.dumps({'encoding': 'concatenated-gzip-chunks', 'files': records}, indent=2) + '\n')


def restore():
    manifest = {item['path']: item for item in json.loads((ROOT / 'native/official/manifest.json').read_text())['files']}
    for record in json.loads(INDEX.read_text())['files']:
        expected = manifest[record['output']]
        if record['sha256'] != expected['sha256'] or record['bytes'] != expected['bytes']:
            raise SystemExit('Chunk index does not match installer identity')
        compressed = bytearray()
        for chunk in record['chunks']:
            data = (INDEX.parent / chunk['path']).read_bytes()
            if len(data) != chunk['bytes'] or digest(data) != chunk['sha256']:
                raise SystemExit('Chunk identity mismatch: ' + chunk['path'])
            compressed.extend(data)
        raw = gzip.decompress(compressed)
        if len(raw) != expected['bytes'] or digest(raw) != expected['sha256']:
            raise SystemExit('Restored installer identity mismatch: ' + record['output'])
        output = ROOT / record['output']
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(raw)
        print('Restored exact installer member: ' + record['output'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pack', action='store_true', help='Analyst operation on supplied original files')
    args = parser.parse_args()
    pack() if args.pack else restore()
