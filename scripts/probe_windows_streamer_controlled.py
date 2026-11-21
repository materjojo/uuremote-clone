#!/usr/bin/env python3
"""Original controlled be-controlled event and OnNewControl ABI observation.

Uses only retained original controller streamer_data and opaque synthetic app
bytes. Supplies no offer, answer or candidates and starts no capture. The
callback copies its three borrowed input slices immediately and never calls
back into the DLL on a native thread.
"""
import ctypes
import json
import threading

from probe_windows_codec_detector import ROOT
from probe_windows_streamer_control import APP_CONTROL_ID, APP_DATA
from probe_windows_streamer_rooms import RoomObservation, binary


class ThreeSlices(ctypes.Structure):
    _fields_ = [('first', ctypes.c_void_p), ('first_size', ctypes.c_int32),
                ('second', ctypes.c_void_p), ('second_size', ctypes.c_int32),
                ('third', ctypes.c_void_p), ('third_size', ctypes.c_int32)]


class ControlledObservation(RoomObservation):
    def __init__(self, role, allow_fixture_ca=False, reply_room_info=False, empty_room_info=False):
        if role != 'controlled' or not reply_room_info or empty_room_info:
            raise ValueError('be-controlled observation requires a valid controlled room_info fixture')
        self.inject_requested = threading.Event()
        self.inject_sent = threading.Event()
        self.new_control_observed = threading.Event()
        self.new_controls = []
        self.callback_errors = []
        self.injected = None
        self.controlled_request_path = None
        self.new_control_callback = ctypes.WINFUNCTYPE(None, ctypes.c_int32, ctypes.c_void_p)(self.record_new_control)
        original = json.loads((ROOT / 'analysis/ci/29a9ea7-windows-control.json').read_text())
        self.original_message = original['observations'][0]['native']['room']['control_request']['message']
        super().__init__(role, allow_fixture_ca, reply_room_info, empty_room_info)

    def install_callback(self, pointers):
        super().install_callback(pointers)
        pointers[10] = ctypes.cast(self.new_control_callback, ctypes.c_void_p).value

    def record_new_control(self, handle, pointer):
        try:
            if not pointer:
                raise ValueError('Null original new-control payload')
            layout = {name: hex(getattr(ThreeSlices, name).offset) for name, _ in ThreeSlices._fields_}
            if ctypes.sizeof(ThreeSlices) != 0x30:
                raise ValueError('Windows x64 three-slice callback layout mismatch')
            inputs = ThreeSlices.from_address(pointer)
            copied = []
            for address, size in ((inputs.first, inputs.first_size),
                                  (inputs.second, inputs.second_size),
                                  (inputs.third, inputs.third_size)):
                if not 0 <= size <= 1024 * 1024 or (size and not address):
                    raise ValueError('Original new-control slice exceeded the observation bound')
                copied.append(ctypes.string_at(address, size) if size else b'')
            # Same three-slice shape as controller input, different meanings.
            self.new_controls.append({'handle': handle, 'input_layout': layout,
                                      'slices': [binary(value) for value in copied],
                                      'first_two_slices_match': copied[:2] == [APP_CONTROL_ID, APP_DATA]})
        except BaseException as error:
            self.callback_errors.append(str(error))
        finally:
            self.new_control_observed.set()

    def on_server_tick(self, send_frame, record):
        if self.controlled_request_path is not None and self.controlled_request_path.exists():
            self.inject_requested.set()
        if self.inject_requested.is_set() and not self.inject_sent.is_set():
            message = {**self.original_message, 'code': 0, 'client_id': 'ci-controller',
                       'ice_id': 'ci-original-control-ice', 'controller_platform': 3, 'iceServers': []}
            packet = '451-["be-controlled",' + json.dumps(message, separators=(',', ':')) + ']'
            send_frame(packet.encode('utf-8'))
            send_frame(b'\x04' + APP_DATA, 2)
            self.injected = {'event': 'be-controlled', 'message': message, 'attachment': binary(b'\x04' + APP_DATA)}
            record['be_controlled_injected'] = True
            self.inject_sent.set()

    def after_room_login(self, table, report):
        if not report.get('room_login_callbacks_observed'):
            raise RuntimeError('Cannot inject be-controlled before native room login')
        self.inject_requested.set()
        report['be_controlled_sent'] = self.inject_sent.wait(3)
        report['new_control_callback_observed'] = self.new_control_observed.wait(8)
        if not report['new_control_callback_observed'] or self.callback_errors:
            raise RuntimeError('Original OnNewControl callback was not observed: ' + repr(self.callback_errors))

    def finish(self, report, *, verify_native=True):
        super().finish(report, verify_native=verify_native)
        report.update(new_control_callback_slot=10, new_control_callback_abi='void(int32_t handle, const ThreeSlices*)',
                      injected_event=self.injected, new_controls=self.new_controls, callback_errors=self.callback_errors)
        if verify_native:
            report['passed'] = (report['passed'] and report.get('be_controlled_sent')
                                and report.get('new_control_callback_observed') and not self.callback_errors
                                and len(self.new_controls) == 1
                                and self.new_controls[0]['handle'] == report.get('handle')
                                and self.new_controls[0]['first_two_slices_match'])
        report['scope'] = 'Original controlled be-controlled event consumption and immediate bounded OnNewControl slice copies.'
        report['limitations'].append('The callback does not establish consent, a connected peer, input or media; no offer, answer or candidate is provided and no capture entry is called.')
