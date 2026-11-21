#!/usr/bin/env python3
"""Observe the packaged original Windows codec detector in GitHub Actions.

This is a CI probe, not a replacement for the DLL's launcher/parser/cache.
The original executable performs all codec discovery. Runner software adapters,
process completion and positive probe flags do not establish physical GPU use.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
FIELDS = ('codec', 'chroma', 'bitdepth', 'width', 'height', 'probe_flag')
RESULT = re.compile(r'RESULT,([+-]?[0-9]+),([+-]?[0-9]+),([+-]?[0-9]+),([+-]?[0-9]+),([+-]?[0-9]+),([+-]?[0-9]+)')
# Original DLL implementation-name switches, not codec IDs or adapter indices.
IMPLEMENTATIONS = {0: 'Nvenc', 1: 'Amd Amf', 2: 'Intel Qsv', 32: 'DXVA11',
                   33: 'NvDec', 38: 'AMF', 39: 'oneVPL'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def summarize_batch(stdout, exit_code, timed_out=False):
    """Strict report validation; the native DLL uses its own scanf-based parser."""
    rows, malformed = [], []
    lines = stdout.splitlines()
    for line in lines:
        if not line.startswith('RESULT,'):
            continue
        match = RESULT.fullmatch(line)
        if not match:
            malformed.append(line)
            continue
        values = tuple(map(int, match.groups()))
        if any(value < -(1 << 31) or value >= (1 << 31) for value in values):
            malformed.append(line)
            continue
        rows.append(dict(zip(FIELDS, values)))
    done = 'BATCH_DONE' in lines
    completed = not timed_out and exit_code == 0 and done and not malformed
    return {
        'batch_done': done,
        'protocol_completed': completed,
        'rows': rows,
        'malformed_result_lines': malformed,
        'batch_errors': [line for line in lines if line.startswith('BATCH_ERROR,')],
        'diagnostics': [line for line in lines if line.startswith('BATCH_DIAG,')],
        # Discard candidate rows from incomplete/failed batches, like the DLL.
        'accepted_rows': rows if completed else [],
        'positive_probe_rows': [row for row in rows if row['probe_flag'] == 1
                                and row['width'] > 0 and row['height'] > 0] if completed else [],
    }


def observe(command, directory, timeout=15):
    started = time.monotonic()
    timed_out = False
    try:
        result = subprocess.run(command, cwd=directory, stdin=subprocess.DEVNULL,
                                capture_output=True, timeout=timeout, check=False)
        stdout, stderr, code = result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired as error:
        # subprocess.run kills and reaps this child on timeout. This CI harness
        # does not emulate the DLL's separate TerminateProcess(..., 9999) code.
        stdout, stderr, code = error.stdout or b'', error.stderr or b'', None
        timed_out = True
    return {
        'command': [str(argument) for argument in command],
        'exit_code': code, 'timed_out': timed_out, 'timeout_seconds': timeout,
        'duration_seconds': round(time.monotonic() - started, 3),
        'stdout': stdout.decode('utf-8', errors='replace'),
        'stderr': stderr.decode('utf-8', errors='replace'),
        'stdout_base64': base64.b64encode(stdout).decode('ascii'),
        'stderr_base64': base64.b64encode(stderr).decode('ascii'),
        'stdout_sha256': digest(stdout), 'stderr_sha256': digest(stderr),
    }


def probe(runtime, adapter_tool):
    if platform.system() != 'Windows' or os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('Original target execution is restricted to Windows GitHub Actions')
    runtime, adapter_tool = runtime.resolve(), adapter_tool.resolve()
    manifest = json.loads((ROOT / 'native/official/manifest.json').read_text())
    identities = []
    for item in manifest['files']:
        if item['platform'] != 'windows':
            continue
        path = runtime / Path(item['path']).name
        data = path.read_bytes()
        if len(data) != item['bytes'] or digest(data) != item['sha256']:
            raise RuntimeError('Packaged original identity mismatch: ' + str(path))
        identities.append({'file': path.name, 'sha256': digest(data), 'bytes': len(data)})
    detector = runtime / 'StreamerCodecDetector.exe'
    observations, failures = [], []
    # Real CLI boundary calls must fail in the expected way, rather than fail
    # to load due to a missing dependency or terminate through a native crash.
    cases = [([], 1, 'Usage: StreamerCodecDetector'),
             (['--batch', 'x', '0', '0'], 2, 'BATCH_ERROR,failed to parse params'),
             (['--batch', '0', '4294967296', '0'], 2, 'BATCH_ERROR,failed to parse params'),
             (['--batch', '0', '0', '18446744073709551616'], 2, 'BATCH_ERROR,failed to parse params'),
             (['--batch', '0', '1x', '0'], 2, 'BATCH_ERROR,failed to parse params')]
    for arguments, expected_code, expected_text in cases:
        record = observe([str(detector), *arguments], runtime)
        record['kind'] = 'cli-boundary'
        record['expected_exit_code'] = expected_code
        record['passed'] = not record['timed_out'] and record['exit_code'] == expected_code and expected_text in record['stdout']
        if not record['passed']:
            failures.append('CLI boundary mismatch: ' + repr(arguments))
        observations.append(record)
    inventory = observe([str(adapter_tool)], runtime)
    adapters = []
    if inventory['timed_out'] or inventory['exit_code'] != 0:
        failures.append('DXGI inventory failed: ' + inventory['stderr'])
    else:
        adapters = json.loads(inventory['stdout'])
    for adapter in adapters:
        for implementation, label in IMPLEMENTATIONS.items():
            record = observe([str(detector), '--batch', str(implementation),
                              str(adapter['device_id']), adapter['adapter_id']], runtime)
            record.update(kind='adapter-batch', implementation=implementation,
                          implementation_name=label, adapter=adapter)
            record.update(summarize_batch(record['stdout'], record['exit_code'], record['timed_out']))
            # An unavailable backend is a valid observed probe failure; an
            # unexplained loader error/crash or malformed successful batch is not.
            record['passed'] = (record['timed_out'] or record['protocol_completed']
                                or (record['exit_code'] == 1 and bool(record['batch_errors'])
                                    and not record['batch_done']))
            if not record['passed']:
                failures.append(f'Unexpected detector response: {implementation} / {adapter["adapter_id"]}')
            observations.append(record)
    return {
        'source_commit': os.environ.get('GITHUB_SHA'), 'run_id': os.environ.get('GITHUB_RUN_ID'),
        'platform': platform.platform(), 'machine': platform.machine(),
        'packaged_original_files': identities,
        'adapter_inventory': inventory, 'adapters': adapters,
        'adapter_input_source': 'DXGI_ADAPTER_DESC1 DeviceId and unsigned AdapterLuid bits; not adapter ordinal',
        'adapter_tool_sha256': digest(adapter_tool.read_bytes()),
        'observations': observations, 'failures': failures,
        'scope': 'Packaged original detector CLI and adapter batches on the hosted runner only; no original DLL Initialize, cache write, capture or media session.',
        'limitations': [
            'Adapters marked with DXGI_ADAPTER_FLAG_SOFTWARE (2) are software renderers.',
            'Protocol completion and positive probe flags are not proof of physical hardware acceleration.',
            'Timeouts and unavailable backends are recorded, not counted as successful batches.',
            'DeviceId/LUID inputs are supplied by this harness; native DLL policy and cache selection are not exercised.',
            'No display capture, encoded media output, hardware frame decoding or mixed-platform session is validated.',
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--adapter-tool', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = probe(args.runtime, args.adapter_tool)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    counts = {'cli_cases': sum(item['kind'] == 'cli-boundary' for item in report['observations']),
              'adapters': len(report['adapters']),
              'completed_batches': sum(item.get('protocol_completed', False) for item in report['observations']),
              'positive_probe_rows': sum(len(item.get('positive_probe_rows', [])) for item in report['observations']),
              'failures': report['failures']}
    print(json.dumps(counts, indent=2))
    return 1 if report['failures'] else 0


if __name__ == '__main__':
    sys.exit(main())
