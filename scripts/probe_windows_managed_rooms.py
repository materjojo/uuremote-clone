#!/usr/bin/env python3
"""Actions-only production room binding checks with explicit fixture CA instrumentation."""
import argparse
import json
import os
from pathlib import Path
import platform
import sys

from probe_windows_codec_detector import observe
from probe_windows_streamer_lifecycle import collect_workspace, save
from probe_windows_streamer_rooms import RoomObservation
from probe_windows_streamer_control import ControlObservation
from probe_windows_streamer_controlled import ControlledObservation


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ('probe', 'runtime', 'workspace', 'output'):
        parser.add_argument('--' + option, type=Path, required=True)
    args = parser.parse_args()
    if platform.system() != 'Windows' or os.environ.get('GITHUB_ACTIONS') != 'true':
        parser.error('Compiled application tests require Windows GitHub Actions')
    probe, runtime, workspace, output = (value.resolve() for value in
        (args.probe, args.runtime, args.workspace, args.output))
    cases = []
    for role in ('controller', 'controlled'):
        role_workspace = workspace / role
        role_workspace.mkdir(parents=True, exist_ok=False)
        fixture_type = ControlObservation if role == 'controller' else ControlledObservation
        fixture = fixture_type(role, allow_fixture_ca=True, reply_room_info=True)
        if role == 'controller':
            fixture.control_observation_path = role_workspace / 'control-observed.json'
        else:
            fixture.controlled_request_path = role_workspace / 'request-controlled-event.json'
        fixture.baseline_rejection_path = role_workspace / 'baseline-rejection.json'
        settings = role_workspace / 'fixture.json'
        save(settings, {'server_url': fixture.url, 'certificate_pem': fixture.certificate_pem,
                        'baseline_rejection_path': str(fixture.baseline_rejection_path),
                        'control_observation_path': str(fixture.control_observation_path) if role == 'controller' else None,
                        'controlled_request_path': str(fixture.controlled_request_path) if role == 'controlled' else None})
        child_output = output.with_name('streamer-managed-room-' + role + '.json')
        transcript = {}
        try:
            result = observe(['dotnet', str(probe), '--room', role, str(runtime),
                              str(role_workspace), str(child_output), str(settings)], runtime, timeout=120)
            managed = json.loads(child_output.read_text(encoding='utf-8')) if child_output.exists() else None
        finally:
            fixture.finish(transcript, verify_native=False)
        # Native callbacks are delivered in the compiled child, not this parent.
        transcript.pop('states', None)
        transcript.pop('state_codes', None)
        transcript['scope'] = 'TLS/Socket.IO fixture transcript only; native callbacks are in the managed child report.'
        replies = [item['room_info_reply'] for item in fixture.connections if 'room_info_reply' in item]
        transport_passed = (fixture.untrusted_certificate_rejected.is_set()
                            and len(replies) == 2 and transcript['listener_stopped']
                            and (role != 'controller' or (len(fixture.observed_controls) == 2
                                 and all(item['input_fields_match'] for item in fixture.observed_controls)))
                            and (role != 'controlled' or fixture.inject_sent.is_set()))
        passed = (transport_passed and result['exit_code'] == 0 and not result['timed_out']
                  and managed is not None and managed.get('passed', False))
        cases.append({'role': role, 'process': result, 'managed': managed, 'fixture': transcript,
                      'workspace_files': collect_workspace(role_workspace), 'passed': passed})
        print(json.dumps({'role': role, 'passed': passed, 'phase': managed.get('phase') if managed else None,
                          'exit_code': result['exit_code'], 'timed_out': result['timed_out'],
                          'room_info_replies': len(replies)}))
    report = {'source_commit': os.environ.get('GITHUB_SHA'), 'run_id': os.environ.get('GITHUB_RUN_ID'),
              'observations': cases, 'passed': all(case['passed'] for case in cases),
              'scope': 'Production C# room entry, native login callbacks, controller request wire bytes and cleanup against an independent local room-info fixture.',
              'instrumentation': 'Each compiled child explicitly adds the fixture CA to its native store after baseline rejection. This is test-only, outside production binding.',
              'limitations': ['Control requests are recorded without ACK or peer consent; no real peer, completed control, input, capture, codec or media session is tested.',
                              'Synthetic room identities are fixtures, not NetEase credentials or business-server responses.',
                              'The ordinary app UI still uses its independent experimental peer path.']}
    save(output, report)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
