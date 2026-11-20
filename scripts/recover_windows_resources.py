#!/usr/bin/env python3
"""Recover the Qt v3 resource tree from the exact supplied 4.48.1.5606 UI image.

Offsets are static derivations from qRegisterResourceData's x64 arguments at
VA 0x140205dce. REA import evidence independently identifies the Qt5 import.
This parser does not execute the PE or claim to recover widget geometry.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
TREE, NAMES, DATA = 0x3A1A2A0, 0x3A098F0, 0x211DDB0
MAX_RESOURCE = 64 * 1024 * 1024


def recover(binary, extract=None):
    evidence = json.loads((ROOT / 'analysis/official/windows-ui-imports.json').read_text())
    expected = evidence['normalized_result']['artifact']['sha256']
    raw = binary.read_bytes()
    sha = hashlib.sha256(raw).hexdigest()
    if sha != expected:
        raise ValueError('Only the authenticated 4.48.1.5606 GameViewer.exe is supported')
    entries, visited, paths = [], set(), set()

    def bounded(offset, size):
        if offset < 0 or size < 0 or offset + size > len(raw):
            raise ValueError('Out-of-image resource reference')
        return raw[offset:offset + size]

    def walk(index, parent):
        if index in visited or len(visited) >= 10000:
            raise ValueError('Resource tree cycle or node budget exceeded')
        visited.add(index)
        at = TREE + index * 22
        node = bounded(at, 22)
        name_offset, flags = struct.unpack_from('>IH', node)
        if flags & ~7:
            raise ValueError('Unknown Qt flags')
        size = struct.unpack('>H', bounded(NAMES + name_offset, 2))[0]
        name = bounded(NAMES + name_offset + 6, size * 2).decode('utf-16-be') if index else ''
        if name in ('.', '..') or '/' in name or '\\' in name:
            raise ValueError('Unsafe Qt resource name')
        path = '/'.join(filter(None, (parent, name)))
        if flags & 2:
            count, first = struct.unpack_from('>II', node, 6)
            if count > 10000:
                raise ValueError('Child budget exceeded')
            for child in range(first, first + count):
                walk(child, path)
            return
        country, language, relative = struct.unpack_from('>HHI', node, 6)
        offset = DATA + relative
        stored_size = struct.unpack('>I', bounded(offset, 4))[0]
        if stored_size > MAX_RESOURCE:
            raise ValueError('Resource byte budget exceeded')
        stored = bounded(offset + 4, stored_size)
        if flags & 4:
            raise ValueError('Unexpected Zstandard member in the observed zlib-enabled target')
        if flags & 1:
            expected_size = struct.unpack('>I', stored[:4])[0]
            if expected_size > MAX_RESOURCE:
                raise ValueError('Decompression byte budget exceeded')
            decoder = zlib.decompressobj()
            decoded = decoder.decompress(stored[4:], expected_size + 1)
            if len(decoded) != expected_size or not decoder.eof or decoder.unused_data:
                raise ValueError('Invalid Qt qCompress payload')
        else:
            decoded = stored
        if path in paths:
            raise ValueError('Localized/duplicate path needs explicit extraction policy')
        paths.add(path)
        entries.append({'path': path, 'node_index': index, 'node_file_offset': at,
                        'flags': flags, 'country': country, 'language': language,
                        'stored_file_offset': offset + 4, 'stored_bytes': stored_size,
                        'stored_sha256': hashlib.sha256(stored).hexdigest(),
                        'bytes': len(decoded), 'sha256': hashlib.sha256(decoded).hexdigest()})
        if extract:
            target = extract.joinpath(*PurePosixPath(path).parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(decoded)

    walk(0, '')
    return {
        'subject': {'file': 'GameViewer.exe', 'sha256': sha, 'bytes': len(raw)},
        'authority': 'static derivation from the supplied artifact; not runtime UI evidence',
        'import_evidence_id': evidence['evidence_id'],
        'registration': {
            'call_va': '0x140205dce', 'import_thunk_va': '0x140820526', 'iat_va': '0x1449ba010',
            'version': 3, 'tree_file_offset': TREE, 'names_file_offset': NAMES, 'data_file_offset': DATA,
            'argument_instructions': [
                '0x140205db4 lea r9,[rip+0x1f199f5]', '0x140205dbb mov ecx,3',
                '0x140205dc0 lea r8,[rip+0x3805529]', '0x140205dc7 lea rdx,[rip+0x3815ed2]']},
        'nodes': len(visited), 'resource_count': len(entries),
        'limitations': ['No widget geometry, visual state, live layout or original source code recovered.',
                        'Full inventory includes cloud resource names; product reuse uses an explicit non-cloud subset.'],
        'resources': sorted(entries, key=lambda e: e['path'])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('--extract', type=Path)
    parser.add_argument('--manifest', type=Path, default=ROOT / 'analysis/official/windows-ui-resources.json')
    args = parser.parse_args()
    record = recover(args.binary, args.extract)
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(json.dumps(record, indent=2) + '\n')
    print(f"Recovered {record['resource_count']} Qt resources from {record['nodes']} nodes: {args.manifest}")


if __name__ == '__main__':
    main()
