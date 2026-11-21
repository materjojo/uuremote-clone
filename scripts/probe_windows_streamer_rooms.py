#!/usr/bin/env python3
"""Runner-only observation of original Windows room setup against loopback.

This recorder supplies TLS and standard Engine.IO/Socket.IO transport setup,
then records the original client's events. An explicit option also supplies a
synthetic room_info response and requires native login callbacks. Native input
layout is specific to the manifest's original x64 DLL.
"""
import base64
import ctypes
import hashlib
import json
import os
import pathlib
import shutil
import socket
import ssl
import struct
import subprocess
import tempfile
import threading
import time
from urllib.parse import parse_qs, urlsplit

from probe_windows_codec_detector import digest


class RoomConfig(ctypes.Structure):
    _fields_ = [('token', ctypes.c_void_p), ('token_size', ctypes.c_int32),
                ('servers', ctypes.c_void_p), ('server_sizes', ctypes.c_void_p),
                ('server_count', ctypes.c_int32), ('timeout', ctypes.c_int32),
                ('reconnect_delay', ctypes.c_int32),
                ('report_token', ctypes.c_void_p), ('report_token_size', ctypes.c_int32),
                ('report_url', ctypes.c_void_p), ('report_url_size', ctypes.c_int32),
                ('report_server', ctypes.c_void_p), ('report_server_size', ctypes.c_int32),
                ('report_option', ctypes.c_int32),
                ('proxy_type', ctypes.c_int32), ('proxy_host', ctypes.c_void_p),
                ('proxy_host_size', ctypes.c_int32), ('proxy_port', ctypes.c_int32),
                ('proxy_username', ctypes.c_void_p), ('proxy_username_size', ctypes.c_int32),
                ('proxy_password', ctypes.c_void_p), ('proxy_password_size', ctypes.c_int32),
                ('sni_servers', ctypes.c_void_p), ('sni_server_sizes', ctypes.c_void_p),
                ('sni_server_count', ctypes.c_int32),
                ('streamer_config', ctypes.c_void_p), ('streamer_config_size', ctypes.c_int32)]


def validate_layout():
    expected = {'token': 0, 'token_size': 8, 'servers': 0x10, 'server_sizes': 0x18,
                'server_count': 0x20, 'timeout': 0x24, 'reconnect_delay': 0x28,
                'report_token': 0x30, 'report_token_size': 0x38, 'report_url': 0x40,
                'report_url_size': 0x48, 'report_server': 0x50, 'report_server_size': 0x58,
                'report_option': 0x5c, 'proxy_type': 0x60, 'proxy_host': 0x68,
                'proxy_host_size': 0x70, 'proxy_port': 0x74, 'proxy_username': 0x78,
                'proxy_username_size': 0x80, 'proxy_password': 0x88, 'proxy_password_size': 0x90,
                'sni_servers': 0x98, 'sni_server_sizes': 0xa0, 'sni_server_count': 0xa8,
                'streamer_config': 0xb0, 'streamer_config_size': 0xb8}
    if ctypes.sizeof(RoomConfig) != 0xc0 or any(getattr(RoomConfig, key).offset != offset for key, offset in expected.items()):
        raise RuntimeError('Original Windows x64 room configuration layout mismatch')
    return {key: hex(value) for key, value in expected.items()}


def binary(data):
    return {'bytes': len(data), 'base64': base64.b64encode(data).decode('ascii'), 'sha256': digest(data)}


class RoomObservation:
    def __init__(self, role, allow_fixture_ca=False, reply_room_info=False, empty_room_info=False):
        self.role = role
        self.allow_fixture_ca = allow_fixture_ca
        self.reply_room_info = reply_room_info
        self.empty_room_info = empty_room_info
        self.baseline_rejection_path = None
        self.states = []
        self.state_codes = []
        self.frames = []
        self.server_frames = []
        self.connections = []
        self.received_event = threading.Event()
        self.untrusted_certificate_rejected = threading.Event()
        self.logged_in = threading.Event()
        self.room_info_rejected = threading.Event()
        self.stop = threading.Event()
        callback_type = ctypes.WINFUNCTYPE(None, ctypes.c_int32, ctypes.c_int32)
        self.callback = callback_type(self.record_state)
        self.code_callback = callback_type(self.record_code)
        self.certificate_directory = tempfile.TemporaryDirectory(prefix='streamer-loopback-tls-')
        certificate = pathlib.Path(self.certificate_directory.name) / 'certificate.pem'
        key = certificate.with_name('private-key.pem')
        openssl = shutil.which('openssl') or r'C:\Program Files\Git\usr\bin\openssl.exe'
        generated = subprocess.run([openssl, 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                                    '-keyout', str(key), '-out', str(certificate), '-days', '1',
                                    '-subj', '/CN=localhost', '-addext', 'subjectAltName=IP:127.0.0.1,DNS:localhost',
                                    '-addext', 'basicConstraints=critical,CA:TRUE'],
                                   capture_output=True, timeout=20)
        if generated.returncode:
            raise RuntimeError('Ephemeral TLS fixture generation failed: ' + generated.stderr.decode('utf-8', errors='replace'))
        self.certificate_pem = certificate.read_text()
        self.tls_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.tls_context.load_cert_chain(str(certificate), str(key))
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.bind(('127.0.0.1', 0))
        self.listener.listen(4)
        self.listener.settimeout(0.2)
        self.port = self.listener.getsockname()[1]
        self.url = f'wss://127.0.0.1:{self.port}/ci-room'
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()
        self.buffers = []  # retain borrowed native inputs through Finalize

    def record_state(self, handle, state):
        self.states.append({'handle': handle, 'state': state})
        self.check_login(handle)

    def record_code(self, handle, code):
        self.state_codes.append({'handle': handle, 'code': code})
        self.check_login(handle)
        if code == 2007:
            self.room_info_rejected.set()

    def check_login(self, handle):
        if (any(item == {'handle': handle, 'state': 2} for item in self.states)
                and any(item == {'handle': handle, 'code': 9003} for item in self.state_codes)
                and any(item == {'handle': handle, 'code': 9004} for item in self.state_codes)):
            self.logged_in.set()

    def install_callback(self, pointers):
        pointers[7 if self.role == 'controller' else 4] = ctypes.cast(self.callback, ctypes.c_void_p).value
        pointers[12] = ctypes.cast(self.code_callback, ctypes.c_void_p).value

    def room_info(self):
        if self.empty_room_info:
            return {}
        participant = {'client_id': 'ci-' + self.role, 'device_id': 'ci-device-' + self.role,
                       'user_id': 'ci-user', 'role': 'publisher' if self.role == 'controlled' else 'subscriber'}
        info = {'room_id': 'ci-loopback-room', 'you': participant, 'subscribers': [],
                'iceServers': [], 'reconnect_buffer': 0}
        if self.role == 'controlled':
            info['publisher'] = participant.copy()
        return info

    def serve(self):
        while not self.stop.is_set():
            try:
                connection, peer = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            record = {'peer': list(peer), 'upgrade_completed': False,
                      'received_stream_layer': 'TLS-decrypted application bytes'}
            transcript = bytearray()
            self.connections.append(record)
            try:
                connection.settimeout(3)
                with self.tls_context.wrap_socket(connection, server_side=True) as connection:
                    record['tls_version'] = connection.version()
                    record['tls_cipher'] = connection.cipher()
                    connection.settimeout(0.25)
                    data = bytearray()
                    deadline = time.monotonic() + 20

                    def receive_until(size):
                        while len(data) < size:
                            if self.stop.is_set() or time.monotonic() >= deadline:
                                raise TimeoutError('Loopback observation ended')
                            try:
                                chunk = connection.recv(4096)
                            except socket.timeout:
                                continue
                            if not chunk:
                                raise EOFError('Native client closed the loopback socket')
                            data.extend(chunk)
                            transcript.extend(chunk)
                            if len(transcript) > 256 * 1024:
                                raise ValueError('Loopback input exceeded bound')

                    while b'\r\n\r\n' not in data:
                        receive_until(len(data) + 1)
                        if len(data) > 16384:
                            raise ValueError('Upgrade header exceeded bound')
                    end = data.index(b'\r\n\r\n') + 4
                    request = bytes(data[:end])
                    del data[:end]
                    record['request'] = binary(request)
                    record['request']['text'] = request.decode('ascii', errors='replace')
                    lines = request.decode('ascii').split('\r\n')
                    headers = dict((key.strip().lower(), value.strip()) for key, value in
                                   (line.split(':', 1) for line in lines[1:] if ':' in line))
                    if not lines[0].startswith('GET /') or headers.get('upgrade', '').lower() != 'websocket':
                        raise ValueError('Unexpected upgrade request')
                    query = parse_qs(urlsplit(lines[0].split(' ')[1]).query)
                    if query.get('EIO') != ['4'] or query.get('transport') != ['websocket']:
                        raise ValueError('Expected Engine.IO v4 WebSocket transport')
                    record['engine_io_query'] = query
                    if headers.get('x-nrd-auth') != 'ci-loopback-token':
                        raise ValueError('Expected the isolated fixture token')
                    key = headers['sec-websocket-key']
                    if len(base64.b64decode(key, validate=True)) != 16:
                        raise ValueError('Invalid WebSocket client key')
                    accept = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode('ascii')).digest())
                    response = b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + b'\r\n\r\n'
                    connection.sendall(response)
                    record['response'] = binary(response)
                    record['upgrade_completed'] = True

                    def send_frame(payload, opcode=1):
                        if len(payload) > 65535:
                            raise ValueError('Fixture frame exceeded bound')
                        prefix = bytes([128 | opcode, len(payload)]) if len(payload) < 126 else bytes([128 | opcode, 126]) + struct.pack('!H', len(payload))
                        wire = prefix + payload
                        connection.sendall(wire)
                        self.server_frames.append({'opcode': opcode, 'wire': binary(wire), 'payload': binary(payload)})

                    def send_text(value):
                        send_frame(value.encode('utf-8'))

                    sid = f'ci-engine-{self.role}-{len(self.connections)}'
                    send_text('0' + json.dumps({'sid': sid, 'upgrades': [], 'pingInterval': 25000,
                                               'pingTimeout': 20000, 'maxPayload': 262144}, separators=(',', ':')))
                    while not self.stop.is_set():
                        receive_until(2)
                        first, second = data[0], data[1]
                        size, offset = second & 127, 2
                        if size == 126:
                            receive_until(4)
                            size, offset = struct.unpack('!H', data[2:4])[0], 4
                        elif size == 127:
                            receive_until(10)
                            size, offset = struct.unpack('!Q', data[2:10])[0], 10
                        if size > 256 * 1024 or not second & 128:
                            raise ValueError('Unmasked or oversized native client frame')
                        receive_until(offset + 4 + size)
                        mask = data[offset:offset + 4]
                        payload = bytes(value ^ mask[index % 4] for index, value in enumerate(data[offset + 4:offset + 4 + size]))
                        wire = bytes(data[:offset + 4 + size])
                        del data[:offset + 4 + size]
                        frame = {'fin': bool(first & 128), 'reserved_bits': (first >> 4) & 7,
                                 'opcode': first & 15, 'masked': True, 'wire': binary(wire), 'payload': binary(payload)}
                        self.frames.append(frame)
                        opcode = first & 15
                        if opcode == 1:
                            frame['text'] = payload.decode('utf-8')
                            if frame['fin'] and frame['reserved_bits'] == 0:
                                if payload == b'40' or payload.startswith(b'40{'):
                                    send_text('40' + json.dumps({'sid': f'ci-socket-{self.role}'}, separators=(',', ':')))
                                    record['namespace_connected'] = True
                                elif record.get('namespace_connected') and payload.startswith((b'42', b'45')):
                                    self.received_event.set()
                                    if self.reply_room_info and payload.startswith(b'42'):
                                        packet = payload[2:].decode('utf-8')
                                        offset = packet.find('[')
                                        if offset >= 0:
                                            acknowledgement, event = packet[:offset], json.loads(packet[offset:])
                                            if event == ['room_info'] and acknowledgement.isdecimal():
                                                info = self.room_info()
                                                send_text('43' + acknowledgement + json.dumps([info], separators=(',', ':')))
                                                record['room_info_reply'] = info
                        elif opcode == 9:
                            send_frame(payload, 10)
                        elif opcode == 8:
                            send_frame(payload, 8)
                            break
            except (OSError, TimeoutError, EOFError, ValueError, KeyError) as error:
                record['end_reason'] = str(error)
                if getattr(error, 'reason', None) == 'TLSV1_ALERT_UNKNOWN_CA':
                    record['untrusted_certificate_rejected'] = True
                    self.untrusted_certificate_rejected.set()
                    if self.baseline_rejection_path is not None:
                        self.baseline_rejection_path.write_text(json.dumps({'peer': list(peer), 'reason': error.reason}), encoding='utf-8')
            finally:
                record['received_stream'] = binary(bytes(transcript))

    def extend_fixture_trust(self, module):
        """Explicit test instrumentation, never a product CA or verification override.

        Reuse the original root loader's DER parse/add/release sequence. The
        shared store already exists because a normal TLS attempt was rejected.
        No code patch, global pointer write or certificate-verification bypass.
        """
        if os.name != 'nt' or os.environ.get('GITHUB_ACTIONS') != 'true':
            raise RuntimeError('Fixture trust instrumentation is restricted to Windows Actions')
        if digest(pathlib.Path(module._name).read_bytes()) != 'ac351cf4e1d489e0b6e1a3df5cdf8aed96348876f7e2c7fcf7162fe59e1bb1c4':
            raise RuntimeError('Fixture trust instrumentation requires the original DLL identity')
        store = ctypes.c_void_p.from_address(module._handle + 0x143f880).value
        if not store:
            raise RuntimeError('Original cached certificate store is not initialized')
        der = ssl.PEM_cert_to_DER_cert(self.certificate_pem)
        buffer = ctypes.create_string_buffer(der)
        cursor = ctypes.c_void_p(ctypes.addressof(buffer))
        parse = ctypes.WINFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p), ctypes.c_int32)(module._handle + 0xd5d110)
        add = ctypes.WINFUNCTYPE(ctypes.c_int32, ctypes.c_void_p, ctypes.c_void_p)(module._handle + 0xe105d0)
        release = ctypes.WINFUNCTYPE(None, ctypes.c_void_p)(module._handle + 0xd5d040)
        certificate = parse(None, ctypes.byref(cursor), len(der))
        if not certificate:
            raise RuntimeError('Original certificate DER parser rejected the fixture')
        try:
            if cursor.value != ctypes.addressof(buffer) + len(der):
                raise RuntimeError('Original certificate parser did not consume the full DER')
            status = add(store, certificate)
            if status != 1:
                raise RuntimeError('Original certificate store rejected the fixture CA')
        finally:
            release(certificate)
        return {'kind': 'instrumented addition of exactly the fixture certificate to this child native store',
                'certificate_der_sha256': digest(der), 'add_status': status,
                'store_pointer_unchanged': ctypes.c_void_p.from_address(module._handle + 0x143f880).value == store,
                'rvas': {'cached_store': '0x143f880', 'parse_der': '0xd5d110', 'add_certificate': '0xe105d0', 'release_certificate': '0xd5d040'},
                'lifetime': 'This isolated child process only; no system trust store or original DLL file is modified.'}

    def observe(self, table, module, report):
        layout = validate_layout()
        token = b'ci-loopback-token'
        encoded_url = self.url.encode('ascii')
        token_buffer, server_buffer = ctypes.create_string_buffer(token), ctypes.create_string_buffer(encoded_url)
        servers = (ctypes.c_void_p * 1)(ctypes.addressof(server_buffer))
        lengths = (ctypes.c_int32 * 1)(len(encoded_url))
        config = RoomConfig(token=ctypes.addressof(token_buffer), token_size=len(token),
                            servers=ctypes.addressof(servers), server_sizes=ctypes.addressof(lengths),
                            server_count=1, timeout=3000, reconnect_delay=1000)
        self.buffers.extend([token_buffer, server_buffer, servers, lengths, config])
        create = ctypes.WINFUNCTYPE(ctypes.c_int32, ctypes.POINTER(RoomConfig))(table[2])
        destroy = ctypes.WINFUNCTYPE(ctypes.c_int32, ctypes.c_int32)(table[3])
        report.update({'server_url': self.url, 'token': token.decode('ascii'), 'config_layout': layout,
                  'proxy_type': 0, 'report_endpoints': [], 'streamer_config_size': 0,
                  'room_callback_slot': 7 if self.role == 'controller' else 4,
                  'room_callback_abi': 'void(int32_t handle, int32_t state)',
                  'connection_code_callback_slot': 12,
                  'connection_code_callback_abi': 'void(int32_t handle, int32_t code)',
                  'reply_room_info': self.reply_room_info, 'empty_room_info': self.empty_room_info})
        report['handle'] = create(ctypes.byref(config))
        try:
            if report['handle'] <= 0:
                raise RuntimeError('Original room entry did not return a positive handle')
            if self.allow_fixture_ca:
                report['baseline_untrusted_certificate_rejected'] = self.untrusted_certificate_rejected.wait(5)
                if not report['baseline_untrusted_certificate_rejected']:
                    raise RuntimeError('Expected the ordinary native TLS attempt to reject the fixture CA')
                report['trust_extension'] = self.extend_fixture_trust(module)
            report['event_frame_observed'] = self.received_event.wait(8)
            if self.reply_room_info:
                if self.empty_room_info:
                    report['empty_room_info_rejected'] = self.room_info_rejected.wait(8)
                else:
                    report['room_login_callbacks_observed'] = self.logged_in.wait(8)
        finally:
            if report['handle'] > 0:
                report['destroy_status'] = destroy(report['handle'])
        return report

    def finish(self, report, *, verify_native=True):
        self.stop.set()
        self.listener.close()
        self.thread.join(timeout=2)
        report.update(states=self.states, state_codes=self.state_codes, connections=self.connections, frames=self.frames, server_frames=self.server_frames,
                      listener_stopped=not self.thread.is_alive(), certificate_pem=self.certificate_pem,
                      tls_fixture='Ephemeral self-signed certificate; explicit child-only native trust instrumentation if enabled.')
        self.certificate_directory.cleanup()
        if verify_native:
            report['passed'] = (report.get('handle', 0) > 0 and report.get('destroy_status') == 0
                            and any(item.get('namespace_connected') for item in self.connections)
                            and report.get('event_frame_observed', False) and report['listener_stopped']
                            and any(state['handle'] == report.get('handle') for state in self.states)
                            and (not self.allow_fixture_ca or (report.get('baseline_untrusted_certificate_rejected')
                                 and report.get('trust_extension', {}).get('store_pointer_unchanged')))
                            and (not self.reply_room_info or (any('room_info_reply' in item for item in self.connections)
                                 and (report.get('room_login_callbacks_observed') if not self.empty_room_info else
                                      report.get('empty_room_info_rejected') and not self.logged_in.is_set()))))
        report['scope'] = ('Original room setup against an independent synthetic room_info fixture.' if self.reply_room_info else
                           'Original room setup and loopback TLS/WebSocket observation only.')
        report['limitations'] = ['The optional fixture CA addition changes this process native trust store and is explicitly instrumented evidence, separate from the ordinary baseline.',
                                 ('The room_info response contains synthetic local room/participant data; no other business ACK is supplied.' if self.reply_room_info else
                                  'Fixture replies implement transport OPEN and default-namespace CONNECT only; no business event ACK is supplied.'),
                                 'No real peer, control or media session is provided.',
                                 'Callback state values are recorded without assuming their business meaning.',
                                 'The caller supplied a loopback URL, synthetic token, empty streamer config, no report server and no proxy.']
