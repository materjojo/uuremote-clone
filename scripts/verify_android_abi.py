#!/usr/bin/env python3
"""Check recovered Android glue against frozen APK DEX prototypes (no JNI loading).

--check-evidence verifies inputs/coverage/source hashes without compiling anything.
--classes checks javap output from the Android build produced by GitHub Actions.
"""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'analysis/official/android'


def compiled_members(classpath, name):
    output = subprocess.check_output(
        ['javap', '-classpath', str(classpath), '-p', '-s', '-constants', name], text=True)
    return parse_javap(output, name)


def parse_javap(output, name):
    methods, constants = {}, {}
    declaration = ''
    for line in output.splitlines():
        constant = re.match(r'\s*public static final int (\w+) = (-?\d+);', line)
        if constant:
            constants[constant[1]] = int(constant[2])
        # Method descriptors themselves contain parentheses. Parse them before
        # recognizing declaration lines, otherwise every method disappears.
        if line.lstrip().startswith('descriptor:'):
            if not declaration:
                continue
            descriptor = line.split('descriptor:', 1)[1].strip()
            method = declaration.split('(', 1)[0].split()[-1]
            if method == name:
                method = '<init>'
            methods[(method, descriptor)] = declaration
            declaration = ''
        elif '(' in line and ')' in line:
            declaration = line.strip()
    return methods, constants


def frozen_classes():
    recovered = json.loads((EVIDENCE / 'recovery-manifest.json').read_text())
    selected = {'com.remote.streamer.' + row['path'][:-5].replace('/', '.'): row
                for row in recovered['files']}
    if len(selected) != 22:
        raise SystemExit('Recovery inventory must contain exactly 22 classes')
    records = {}
    for path in sorted(EVIDENCE.glob('*.json')):
        record = json.loads(path.read_text())
        data = record.get('normalized_result', {})
        name = data.get('class_name')
        if name not in selected or not data.get('methods'):
            continue
        if name in records:
            raise SystemExit('Duplicate frozen class evidence: ' + name)
        if record['subject']['digest']['sha256'] != recovered['apk_sha256']:
            raise SystemExit('Class evidence belongs to a different APK: ' + name)
        source = ROOT / 'platforms/android/app/src/main/java/com/remote/streamer' / selected[name]['path']
        if hashlib.sha256(source.read_bytes()).hexdigest() != selected[name]['adapted_sha256']:
            raise SystemExit('Adapted glue differs from the recovery manifest: ' + name)
        records[name] = record
    missing = selected.keys() - records.keys()
    if missing:
        raise SystemExit('Classes without original DEX evidence: ' + ', '.join(sorted(missing)))
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--classes', type=Path)
    mode.add_argument('--check-evidence', action='store_true')
    args = parser.parse_args()
    records = frozen_classes()
    if args.check_evidence:
        print(f'PASS: all {len(records)} recovered classes have matching original APK evidence and source hashes.')
        return
    total, constant_total = 0, 0
    errors = []
    for name, record in sorted(records.items()):
        short = name.rsplit('.', 1)[-1]
        actual, constants = compiled_members(args.classes, name)
        for method in record['normalized_result']['methods']:
            key = (method['name'], method['dex_descriptor'])
            # Static initializers and Kotlin mask constructors were removed as
            # compiler scaffolding. Preserve every other original method.
            if key[0] == '<clinit>' or (key[0] == '<init>' and 'Lle/f;' in key[1]):
                continue
            if key == ('finalize', '()I'):
                key = ('shutdown', '()I')  # Java Object.finalize()V cannot be overridden with int
            native = ((short in ('AndroidStreamerController', 'AndroidStreamerControlled')
                       and key[0][0].isupper()) or key[0].startswith('native'))
            total += 1
            decl = actual.get(key)
            if not decl:
                errors.append(f'{name}.{key[0]}: missing exact {key[1]} [{record["evidence_id"]}]')
            elif ' static ' in f' {decl} ':
                errors.append(f'{name}.{key[0]}: original is an instance method')
            elif native and ' native ' not in f' {decl} ':
                errors.append(f'{name}.{key[0]}: lost native modifier')
        for field in record['normalized_result']['fields']:
            encoded = field['dex_static_value']
            if encoded is None or encoded['type'] != 'int':
                continue  # absent DEX value does not prove a static field's value
            constant_total += 1
            if constants.get(field['name']) != encoded['value']:
                errors.append(f'{name}.{field["name"]}: original encoded constant is {encoded["value"]}')
        print(f'{name}: checked against {record["evidence_id"]}')
    if errors:
        raise SystemExit('\n'.join(errors))
    print(f'PASS: {total} compiled method descriptors and {constant_total} encoded constants across {len(records)} classes.')
    print('Scope: static descriptor agreement; no claim of Android native execution or end-to-end compatibility.')


if __name__ == '__main__':
    main()
