#!/usr/bin/env python3
"""Bounded static Mach-O inspection for the two supplied desktop media slices.

Requires analyst-supplied LIEF and Capstone; does not execute the application.
Keeps file hashes, raw table pointers, instruction bytes, and the selected range.
This is not whole-program decompilation or a runtime observation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import capstone
import lief

PROFILES = {
    'arm64': {
        'factories': {'controller': (0x752c14, 0x995b60), 'controlled': (0x752c30, 0x9950c0)},
        'tables': {'controller': (0xbd7808, 21, 17, 17), 'controlled': (0xbd78b0, 23, 15, 18)},
    },
    'x86_64': {
        'factories': {'controller': (0x8370e0, 0xace5b0), 'controlled': (0x837100, 0xacd950)},
        'tables': {'controller': (0xd1cb88, 21, 17, 17), 'controlled': (0xd1cc30, 23, 15, 18)},
    },
}


def inspect(path, architecture):
    data = path.read_bytes()
    binary = lief.MachO.parse(str(path)).at(0)
    if architecture == 'arm64':
        decoder = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
    else:
        decoder = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    decoder.skipdata = True

    def disassemble(address, size, stop_at_return=False):
        raw = bytes(binary.get_content_from_virtual_address(address, size))
        rows = []
        for ins in decoder.disasm(raw, address):
            rows.append({'address': hex(ins.address), 'bytes': bytes(ins.bytes).hex(),
                         'mnemonic': ins.mnemonic, 'operands': ins.op_str})
            if stop_at_return and ins.mnemonic == 'ret':
                break
        return {'address': hex(address), 'requested_bytes': size,
                'file_offset': binary.virtual_address_to_offset(address), 'instructions': rows}

    result = {'artifact': {'path': str(path), 'sha256': hashlib.sha256(data).hexdigest(),
                          'bytes': len(data), 'architecture': architecture},
              'tools': {'lief': lief.__version__, 'capstone': capstone.__version__},
              'authority': 'shipped-artifact', 'kind': 'bounded-static-disassembly',
              'limitations': ['Selected prefixes and version entries only; no complete control/data-flow recovery.',
                             'No application execution. Pointer tables are file-backed static data, not process memory.',
                             'Capstone skipdata retains undecoded instructions explicitly as data.'], 'roles': {}}
    for role, (factory, helper) in PROFILES[architecture]['factories'].items():
        table, slots, callbacks, version_slot = PROFILES[architecture]['tables'][role]
        raw = bytes(binary.get_content_from_virtual_address(table, slots * 8))
        values = [int.from_bytes(raw[i:i+8], 'little') for i in range(0, len(raw), 8)]
        result['roles'][role] = {
            'factory': disassemble(factory, 64, True),
            'callback_helper_prefix': disassemble(helper, 224),
            'callback_count': callbacks, 'table_address': hex(table),
            'table_file_offset': binary.virtual_address_to_offset(table),
            'table_raw_bytes_sha256': hashlib.sha256(raw).hexdigest(),
            'table_pointer_values': [hex(v) for v in values], 'slot_count': slots,
            'version_slot': version_slot, 'version_entry': disassemble(values[version_slot], 128, True),
        }
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--slices', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    results = [inspect(args.slices / ('libstreamer.dylib.' + arch), arch) for arch in PROFILES]
    args.output.write_text(json.dumps(results, indent=2) + '\n')
    for result in results:
        print(result['artifact'])
        print({role: {'callback_count': data['callback_count'], 'version_slot': data['version_slot']}
               for role, data in result['roles'].items()})


if __name__ == '__main__':
    main()
