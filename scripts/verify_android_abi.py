#!/usr/bin/env python3
"""Check compiled Android glue against frozen APK DEX prototypes (no JNI loading)."""
import argparse
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'analysis/official/android'


def compiled_methods(classpath, name):
    text = subprocess.check_output(['javap', '-classpath', str(classpath), '-p', '-s', name], text=True)
    found = {}
    declaration = ''
    for line in text.splitlines():
        if '(' in line and ')' in line:
            declaration = line.strip()
        elif 'descriptor:' in line and declaration:
            descriptor = line.split('descriptor:', 1)[1].strip()
            method = declaration.split('(', 1)[0].split()[-1]
            if method == name:
                method = '<init>'
            found[(method, descriptor)] = declaration
            declaration = ''
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--classes', type=Path, required=True)
    args = parser.parse_args()
    total = 0
    errors = []
    recovered = json.loads((EVIDENCE / 'recovery-manifest.json').read_text())
    selected = {'com.remote.streamer.' + row['path'][:-5].replace('/', '.')
                for row in recovered['files']}
    for path in sorted(EVIDENCE.glob('*.json')):
        record = json.loads(path.read_text())
        data = record.get('normalized_result', {})
        name = data.get('class_name')
        methods = data.get('methods')
        if name not in selected or not methods:
            continue
        short = name.rsplit('.', 1)[-1]
        if short in ('StreamerControllerCallback', 'StreamerControlledCallback', 'Streamer'):
            continue  # application-level Kotlin interfaces, not JNI callback dispatchers
        actual = compiled_methods(args.classes, name)
        for method in methods:
            key = (method['name'], method['dex_descriptor'])
            native = ((short in ('AndroidStreamerController', 'AndroidStreamerControlled')
                       and key[0][0].isupper()) or key[0].startswith('native'))
            model = '.model.' in name and (key[0].startswith('get') or key[0] == '<init>')
            callback = key[0].startswith('On') or key[0] in (
                'onFrameChange', 'onCaptureFailed', 'clearNativeListener', 'SetNativeGLesRenderer')
            if not (native or model or callback):
                continue
            # Kotlin mask/default constructors do not belong in the Java JNI ABI.
            if key[0] == '<init>' and 'Lle/f;' in key[1]:
                continue
            total += 1
            decl = actual.get(key)
            if not decl:
                errors.append(f'{name}.{key[0]}: missing exact {key[1]} [{record["evidence_id"]}]')
            elif ' static ' in f' {decl} ':
                errors.append(f'{name}.{key[0]}: original is an instance method')
            elif native and ' native ' not in f' {decl} ':
                errors.append(f'{name}.{key[0]}: lost native modifier')
        print(f'{name}: checked against {record["evidence_id"]}')
    if not total:
        raise SystemExit('No ABI contracts checked')
    if errors:
        raise SystemExit('\n'.join(errors))
    print(f'PASS: {total} compiled native/getter/constructor/callback descriptors match the supplied APK.')
    print('Scope: static descriptor agreement; no claim of Android native execution or end-to-end compatibility.')


if __name__ == '__main__':
    main()
