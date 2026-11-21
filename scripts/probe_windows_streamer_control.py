#!/usr/bin/env python3
"""Isolated original Windows controller slot 4 request observation.

The three input slices were traced through the original wrapper, coroutine
copies and Socket.IO serializer. The fixture records the request but supplies
no control ACK, peer, consent decision or media. It keeps the ordinary TLS
rejection and the explicitly instrumented fixture CA addition separate.
"""
import base64
import ctypes
import json
import threading

from probe_windows_streamer_rooms import RoomObservation, binary


APP_DATA = b'ci-control-app-data\x00\xff\xfe'
APP_CONTROL_ID = b'ci-local-control-01'
GEO_TIMEZONE = b'Etc/UTC'


class ConnectInput(ctypes.Structure):
    _fields_ = [('app_data', ctypes.c_void_p), ('app_data_size', ctypes.c_int32),
                ('app_control_id', ctypes.c_void_p), ('app_control_id_size', ctypes.c_int32),
                ('geo_timezone', ctypes.c_void_p), ('geo_timezone_size', ctypes.c_int32)]


def validate_connect_layout():
    expected = {'app_data': 0, 'app_data_size': 8,
                'app_control_id': 0x10, 'app_control_id_size': 0x18,
                'geo_timezone': 0x20, 'geo_timezone_size': 0x28}
    if ctypes.sizeof(ConnectInput) != 0x30 or any(getattr(ConnectInput, key).offset != value for key, value in expected.items()):
        raise RuntimeError('Original Windows x64 controller connect input layout mismatch')
    return {key: hex(value) for key, value in expected.items()}


class ControlObservation(RoomObservation):
    def __init__(self, role, allow_fixture_ca=False, reply_room_info=False, empty_room_info=False):
        if role != 'controller' or not reply_room_info or empty_room_info:
            raise ValueError('Control request observation requires a valid controller room_info fixture')
        self.control_event = threading.Event()
        self.control_attachment = threading.Event()
        self.control_frame_index = None
        self.control_message = None
        self.control_payload = None
        super().__init__(role, allow_fixture_ca, reply_room_info, empty_room_info)

    def on_client_frame(self, frame):
        data = base64.b64decode(frame['payload']['base64'])
        if frame['opcode'] == 1 and frame['fin'] and frame['reserved_bits'] == 0 and data.startswith((b'42', b'45')):
            start = data.find(b'[')
            if start >= 0:
                packet = json.loads(data[start:])
                if isinstance(packet, list) and len(packet) == 2 and packet[0] == 'control':
                    self.control_message = packet[1]
                    self.control_frame_index = len(self.frames) - 1
                    self.control_event.set()
        elif frame['opcode'] == 2 and self.control_frame_index is not None and not self.control_attachment.is_set():
            self.control_payload = data
            self.control_attachment.set()

    def after_room_login(self, table, report):
        request = {'slot': 4, 'abi': 'int32_t(int32_t handle, const ConnectInput*)',
                   'input_size': ctypes.sizeof(ConnectInput), 'input_layout': validate_connect_layout(),
                   'app_data': binary(APP_DATA), 'app_control_id': APP_CONTROL_ID.decode('ascii'),
                   'geo_timezone': GEO_TIMEZONE.decode('ascii'),
                   'control_ack_supplied': False}
        report['control_request'] = request
        if not report.get('room_login_callbacks_observed'):
            raise RuntimeError('Cannot request control before the original login callbacks')
        buffers = [ctypes.create_string_buffer(value) for value in (APP_DATA, APP_CONTROL_ID, GEO_TIMEZONE)]
        inputs = ConnectInput(ctypes.addressof(buffers[0]), len(APP_DATA),
                              ctypes.addressof(buffers[1]), len(APP_CONTROL_ID),
                              ctypes.addressof(buffers[2]), len(GEO_TIMEZONE))
        self.buffers.extend([*buffers, inputs])
        connect = ctypes.WINFUNCTYPE(ctypes.c_int32, ctypes.c_int32, ctypes.POINTER(ConnectInput))(table[4])
        request['status'] = connect(report['handle'], ctypes.byref(inputs))
        request['event_observed'] = self.control_event.wait(8)
        request['attachment_observed'] = self.control_attachment.wait(2)
        request['frame_index'] = self.control_frame_index
        request['message'] = self.control_message
        request['attachment'] = binary(self.control_payload) if self.control_payload is not None else None
        message = self.control_message if isinstance(self.control_message, dict) else {}
        request['input_fields_match'] = (message.get('app_control_id') == APP_CONTROL_ID.decode('ascii')
                                        and message.get('geo_timezone') == GEO_TIMEZONE.decode('ascii')
                                        and message.get('app_data') == {'_placeholder': True, 'num': 0}
                                        and self.control_payload == APP_DATA)
        if request['status'] != 0 or not request['input_fields_match']:
            raise RuntimeError('Original control request did not preserve the three supplied input slices')

    def finish(self, report, *, verify_native=True):
        super().finish(report, verify_native=verify_native)
        request = report.get('control_request', {})
        if verify_native:
            report['passed'] = report['passed'] and request.get('status') == 0 and request.get('input_fields_match', False)
        report['scope'] = 'Original controller room login and slot 4 control request against an independent local recorder.'
        report['limitations'].append('The control event receives no ACK or peer response; a zero request status does not establish consent, control success, ICE or media.')
