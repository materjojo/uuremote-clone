#!/usr/bin/env python3
"""Actions-only two-process original Windows negotiation observation.

A bounded independent TLS/Engine.IO/Socket.IO recorder routes actual engine
requests. No NetEase service, STUN/TURN service, capture or media is supplied.
Both children use the production managed engine and explicit test-only CA trust.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import platform
import queue
import secrets
import subprocess
import sys
import time
import traceback

from probe_windows_streamer_lifecycle import collect_workspace, save
from probe_windows_streamer_rooms import RoomObservation


ROLES = ('controller', 'controlled')
CONTROL_ID = 'ci-local-control-01'
ICE_ID = 'ci-original-pair-ice'


class PairBroker:
    def __init__(self):
        self.endpoints = {}
        self.events = []
        self.routes = []
        self.errors = []
        self.control = None
        self.ack_sent = False

    def send(self, role, event, message, attachments=(), ack=None):
        packet = json.dumps([event, message], separators=(',', ':')) if ack is None else json.dumps(message, separators=(',', ':'))
        prefix = '43' + ack if ack is not None else ('45' + str(len(attachments)) + '-' if attachments else '42')
        frames = [(prefix + packet).encode('utf-8'), *attachments]
        # A frame group stays contiguous, including all binary attachments.
        self.endpoints[role].outgoing.put(frames)
        self.routes.append({'to': role, 'event': event, 'ack': ack, 'attachment_bytes': [len(item) for item in attachments]})

    def receive(self, role, event, message, attachments, acknowledgement):
        self.events.append({'from': role, 'event': event, 'message': message,
                            'ack_id': acknowledgement, 'attachment_bytes': [len(item) for item in attachments]})
        if event == 'control':
            if role != 'controller' or not acknowledgement or self.control is not None or len(attachments) != 1:
                raise ValueError('Unexpected original controller request')
            self.control = {'message': message, 'ack': acknowledgement}
            incoming = {**message, 'code': 0, 'client_id': 'ci-controller', 'ice_id': ICE_ID,
                        'controller_platform': 3, 'iceServers': []}
            self.send('controlled', 'be-controlled', incoming, attachments)
        elif event == 'forward_setting':
            data = message.get('data', {})
            if role == 'controlled' and data.get('type') == 'device_capability' and not self.ack_sent:
                if self.control is None:
                    raise ValueError('Peer capability arrived before the actual control request')
                response = {'code': 0, 'client_id': 'ci-controlled', 'ice_id': ICE_ID,
                            'app_control_id': CONTROL_ID, 'iceServers': [],
                            'streamer_data': json.dumps({'control_id': CONTROL_ID, **data.get('data', {})}, separators=(',', ':'))}
                # forward_setting nests the actual capability beside its type.
                if 'device_capability' in data:
                    response['streamer_data'] = json.dumps({'control_id': CONTROL_ID, 'device_capability': data['device_capability']}, separators=(',', ':'))
                self.send('controller', 'control_ack', ['success', response], ack=self.control['ack'])
                self.ack_sent = True
            else:
                peer = 'controlled' if role == 'controller' else 'controller'
                self.send(peer, event, {**message, 'client_id': 'ci-' + role}, attachments)
        elif event == 'soac':
            # Initial raw guard announcements have no target; retain them only.
            target = message.get('client_id')
            peer = 'controlled' if role == 'controller' else 'controller'
            if target == 'ci-' + peer:
                self.send(peer, 'soac', {**message, 'client_id': 'ci-' + role}, attachments)
        elif event not in ('room_info', 'update_geo_ip', 'leave', 'release'):
            # Preserve unknown events; do not invent a business ACK for them.
            return

    def negotiation_observed(self):
        types = {(item['from'], item['message'].get('data', {}).get('type'))
                 for item in self.events if item['event'] == 'soac'}
        return (self.ack_sent and ('controller', 'offer') in types and ('controlled', 'answer') in types
                and all((role, 'candidate') in types for role in ROLES))


class PairEndpoint(RoomObservation):
    def __init__(self, role, broker):
        self.broker = broker
        self.outgoing = queue.Queue()
        self.pending = None
        self.connection_lifetime = 75
        self.last_ping = time.monotonic()
        super().__init__(role, allow_fixture_ca=True, reply_room_info=True)

    def room_info(self):
        def participant(role):
            return {'client_id': 'ci-' + role, 'device_id': 'ci-device-' + role,
                    'user_id': 'ci-user', 'role': 'publisher' if role == 'controlled' else 'subscriber',
                    'platform': 3, 'version_name': 'independent-native-pair'}
        return {'room_id': 'ci-original-pair', 'you': participant(self.role),
                'publisher': participant('controlled'), 'subscribers': [participant('controller')],
                'iceServers': [], 'reconnect_buffer': 0}

    def on_server_tick(self, send_frame, record):
        while True:
            try:
                frames = self.outgoing.get_nowait()
            except queue.Empty:
                break
            for index, data in enumerate(frames):
                send_frame(data, 1 if index == 0 else 2)
        if time.monotonic() - self.last_ping > 10:
            send_frame(b'2')
            self.last_ping = time.monotonic()

    def on_client_frame(self, frame):
        try:
            data = base64.b64decode(frame['payload']['base64'])
            if frame['opcode'] == 2:
                if self.pending is None:
                    raise ValueError('Binary frame without an original event header')
                self.pending['attachments'].append(data)
                if len(self.pending['attachments']) == self.pending['count']:
                    self.deliver(self.pending)
                    self.pending = None
            elif frame['opcode'] == 1 and data.startswith((b'42', b'45')):
                start = data.find(b'[')
                if start < 0:
                    raise ValueError('Original event lacks a JSON array')
                packet, header = json.loads(data[start:]), data[2:start].decode('ascii')
                count, ack = 0, header
                if data.startswith(b'45'):
                    number, dash, ack = header.partition('-')
                    if not dash or not number.isdecimal() or not 1 <= int(number) <= 16:
                        raise ValueError('Invalid original binary event count')
                    count = int(number)
                if ack and not ack.isdecimal():
                    raise ValueError('Invalid original event ACK id')
                item = {'packet': packet, 'ack': ack, 'count': count, 'attachments': []}
                if self.pending is not None:
                    raise ValueError('Interleaved original binary event')
                if count:
                    self.pending = item
                else:
                    self.deliver(item)
        except (ValueError, TypeError, KeyError, IndexError) as error:
            self.broker.errors.append({'role': self.role, 'error': str(error)})
            raise

    def deliver(self, item):
        packet = item['packet']
        if packet == ['room_info']:
            return  # Base fixture supplies its ACK with this endpoint's identities.
        if not isinstance(packet, list) or not packet or not isinstance(packet[0], str):
            raise ValueError('Unexpected native event shape')
        message = packet[1] if len(packet) == 2 else {}
        if not isinstance(message, dict):
            raise ValueError('Unexpected native event data')
        self.broker.receive(self.role, packet[0], message, item['attachments'], item['ack'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ('probe', 'runtime', 'workspace', 'output'):
        parser.add_argument('--' + option, type=Path, required=True)
    args = parser.parse_args()
    if platform.system() != 'Windows' or os.environ.get('GITHUB_ACTIONS') != 'true':
        parser.error('Original pair execution requires Windows GitHub Actions')
    probe, runtime, workspace, output = [value.resolve() for value in (args.probe, args.runtime, args.workspace, args.output)]
    workspace.mkdir(parents=True, exist_ok=False)
    broker, processes, streams, children, fixtures = PairBroker(), {}, {}, {}, {}
    report = {'source_commit': os.environ.get('GITHUB_SHA'), 'run_id': os.environ.get('GITHUB_RUN_ID'),
              'passed': False, 'scope': 'Two original Windows engines with independently routed signaling and direct original binary-channel transfer.',
              'instrumentation': 'Each child records baseline unknown_ca before explicitly adding only its fixture CA; no production trust override.',
              'limitations': ['This is one host with two processes and private host candidates; it does not establish physical peer interoperability, public IPv4/IPv6 hole punching, capture, decoding or GPU operation.',
                              'Only the original opaque binary send and receive channel is exercised; no capture, renderer, input or audio is called.',
                              'Room, device, user and control identities are test fixtures, not a production authorization service.']}
    payloads = {role: b'ci-native-binary\x00\xff\xfe' + secrets.token_bytes(256) for role in ROLES}
    negotiation_at = None
    def received_by_both():
        return all((workspace / (role + '-received')).exists() for role in ROLES)
    try:
        for role in ROLES:
            endpoint = PairEndpoint(role, broker)
            broker.endpoints[role] = endpoint
            role_workspace = workspace / role
            role_workspace.mkdir()
            endpoint.baseline_rejection_path = role_workspace / 'baseline-rejection.json'
            settings = role_workspace / 'fixture.json'
            save(settings, {'server_url': endpoint.url, 'certificate_pem': endpoint.certificate_pem,
                            'baseline_rejection_path': str(endpoint.baseline_rejection_path),
                            'ready_path': str(workspace / (role + '-ready')),
                            'start_path': str(workspace / 'start'), 'stop_path': str(workspace / 'stop'),
                            'send_path': str(workspace / 'send'),
                            'received_path': str(workspace / (role + '-received')),
                            'send_payload_base64': base64.b64encode(payloads[role]).decode('ascii'),
                            'expected_payload_base64': base64.b64encode(payloads['controlled' if role == 'controller' else 'controller']).decode('ascii')})
            child_output = workspace / (role + '.json')
            stdout, stderr = (role_workspace / 'stdout.txt').open('wb'), (role_workspace / 'stderr.txt').open('wb')
            streams[role] = stdout, stderr
            processes[role] = subprocess.Popen(['dotnet', str(probe), '--pair', role, str(runtime),
                                                str(role_workspace), str(child_output), str(settings)],
                                               cwd=runtime, stdout=stdout, stderr=stderr)
        deadline = time.monotonic() + 65
        while time.monotonic() < deadline:
            if all((workspace / (role + '-ready')).exists() for role in ROLES) and not (workspace / 'start').exists():
                (workspace / 'start').write_text('both original logins observed')
            if broker.negotiation_observed() and negotiation_at is None:
                negotiation_at = time.monotonic()
            if negotiation_at is not None and time.monotonic() - negotiation_at >= 3 and not (workspace / 'send').exists():
                (workspace / 'send').write_text('exercise original binary submission after recorded signaling')
            if (received_by_both() or broker.errors
                    or any(item.poll() is not None for item in processes.values())):
                break
            time.sleep(0.05)
        report['negotiation_signaling_observed'] = broker.negotiation_observed()
        report['bidirectional_binary_observed'] = received_by_both()
    except BaseException:
        report['error'] = traceback.format_exc()
    finally:
        (workspace / 'stop').write_text('end observation')
        for role, process in processes.items():
            try:
                process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
                report.setdefault('killed_roles', []).append(role)
            for stream in streams[role]:
                stream.close()
            child_output = workspace / (role + '.json')
            children[role] = {'exit_code': process.returncode,
                              'managed': json.loads(child_output.read_text(encoding='utf-8')) if child_output.exists() else None}
        for role, endpoint in broker.endpoints.items():
            fixture = {}
            endpoint.finish(fixture, verify_native=False)
            fixture.pop('states', None)
            fixture.pop('state_codes', None)
            fixtures[role] = fixture
        report['binary_bytes_verified'] = len(children) == 2 and all(
            item.get('managed') and item['managed'].get('peer_binary_received')
            and len(item['managed'].get('binary_data', [])) == 1
            and item['managed']['binary_data'][0]['Handle'] == item['managed']['handle']
            and base64.b64decode(item['managed']['binary_data'][0]['Data'])
                == payloads['controlled' if role == 'controller' else 'controller']
            for role, item in children.items())
        report.update(events=broker.events, routes=broker.routes, broker_errors=broker.errors,
                      children=children, fixtures=fixtures, workspace_files=collect_workspace(workspace))
        report['passed'] = (report.get('negotiation_signaling_observed', False) and report.get('bidirectional_binary_observed', False)
                             and report['binary_bytes_verified'] and not broker.errors
                             and len(children) == 2 and not report.get('killed_roles')
                             and all(item['exit_code'] == 0 and item['managed'] and item['managed'].get('passed') for item in children.values())
                             and all(item['listener_stopped'] and any(connection.get('untrusted_certificate_rejected') for connection in item['connections']) for item in fixtures.values()))
        save(output, report)
    print(json.dumps({'passed': report['passed'], 'negotiation_signaling_observed': report.get('negotiation_signaling_observed'),
                      'bidirectional_binary_observed': report.get('bidirectional_binary_observed'),
                      'events': [(item['from'], item['event'], item['message'].get('data', {}).get('type')) for item in broker.events],
                      'broker_errors': broker.errors}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
