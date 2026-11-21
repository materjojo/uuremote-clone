#!/usr/bin/env python3
"""Runner-only observation of original Windows room setup against loopback.

This recorder supplies TLS and standard Engine.IO/Socket.IO transport setup,
then records the original client's events without replying to business requests.
Native input layout is specific to the manifest's original x64 DLL.
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
    def __init__(self, role):
        self.role = role
        self.states = []
        self.frames = []
        self.server_frames = []
        self.connections = []
        self.received_event = threading.Event()
        self.stop = threading.Event()
        self.callback = ctypes.WINFUNCTYPE(None, ctypes.c_int32, ctypes.c_int32)(
            lambda handle, state: self.states.append({'handle': handle, 'state': state}))
        self.certificate_directory = tempfile.TemporaryDirectory(prefix='streamer-loopback-tls-')
        certificate = pathlib.Path(self.certificate_directory.name) / 'certificate.pem'
        key = certificate.with_name('private-key.pem')
        openssl = shutil.which('openssl') or r'C:\Program Files\Git\usr\bin\openssl.exe'
        generated = subprocess.run([openssl, 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                                    '-keyout', str(key), '-out', str(certificate), '-days', '1',
                                    '-subj', '/CN=localhost', '-addext', 'subjectAltName=IP:127.0.0.1,DNS:localhost'],
                                   capture_output=True, timeout=20)
        if generated.returncode:
            raise RuntimeError('Ephemeral TLS fixture generation failed: ' + generated.stderr.decode('utf-8', errors='replace'))
        self.certificate_pem = certificate.read_text()
        self.tls_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.tls_context.load_cert_chain(str(certificate), str(key))
        self.previous_certificate_file = os.environ.get('SSL_CERT_FILE')
        os.environ['SSL_CERT_FILE'] = str(certificate)
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.bind(('127.0.0.1', 0))
        self.listener.listen(4)
        self.listener.settimeout(0.2)
        self.port = self.listener.getsockname()[1]
        self.url = f'wss://127.0.0.1:{self.port}/ci-room'
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()
        self.buffers = []  # retain borrowed native inputs through Finalize

    def install_callback(self, pointers):
        pointers[7 if self.role == 'controller' else 4] = ctypes.cast(self.callback, ctypes.c_void_p).value

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
                    deadline = time.monotonic() + 8

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
                        elif opcode == 9:
                            send_frame(payload, 10)
                        elif opcode == 8:
                            send_frame(payload, 8)
                            break
            except (OSError, TimeoutError, EOFError, ValueError, KeyError) as error:
                record['end_reason'] = str(error)
            finally:
                record['received_stream'] = binary(bytes(transcript))

    def observe(self, table):
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
        report = {'server_url': self.url, 'token': token.decode('ascii'), 'config_layout': layout,
                  'proxy_type': 0, 'report_endpoints': [], 'streamer_config_size': 0,
                  'room_callback_slot': 7 if self.role == 'controller' else 4,
                  'room_callback_abi': 'void(int32_t handle, int32_t state)'}
        report['handle'] = create(ctypes.byref(config))
        try:
            if report['handle'] <= 0:
                raise RuntimeError('Original room entry did not return a positive handle')
            report['event_frame_observed'] = self.received_event.wait(8)
        finally:
            if report['handle'] > 0:
                report['destroy_status'] = destroy(report['handle'])
        return report

    def finish(self, report):
        self.stop.set()
        self.listener.close()
        self.thread.join(timeout=2)
        report.update(states=self.states, connections=self.connections, frames=self.frames, server_frames=self.server_frames,
                      listener_stopped=not self.thread.is_alive(), certificate_pem=self.certificate_pem,
                      tls_fixture='Ephemeral self-signed certificate supplied through this child process SSL_CERT_FILE before loading the DLL. No system trust store changed.')
        if self.previous_certificate_file is None:
            os.environ.pop('SSL_CERT_FILE', None)
        else:
            os.environ['SSL_CERT_FILE'] = self.previous_certificate_file
        self.certificate_directory.cleanup()
        report['passed'] = (report.get('handle', 0) > 0 and report.get('destroy_status') == 0
                            and any(item.get('namespace_connected') for item in self.connections)
                            and report.get('event_frame_observed', False) and report['listener_stopped'])
        report['scope'] = 'Original room setup and loopback TLS/WebSocket observation only.'
        report['limitations'] = ['Fixture replies implement transport OPEN and default-namespace CONNECT only; no business event ACK is supplied.',
                                 'No authenticated room, real peer or media session is provided.',
                                 'Callback state values are recorded without assuming their business meaning.',
                                 'The caller supplied a loopback URL, synthetic token, empty streamer config, no report server and no proxy.']
