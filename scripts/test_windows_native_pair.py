#!/usr/bin/env python3
"""Offline replay of retained original wire records through the pair recorder.

No original DLL, compiled application or transport is executed by these tests.
"""
import json
from pathlib import Path
import queue
import unittest

from probe_windows_native_pair import PairBroker, PairEndpoint, ROLES

ROOT = Path(__file__).resolve().parents[1]


class PairReplayChecks(unittest.TestCase):
    def setUp(self):
        self.broker = PairBroker()
        for role in ROLES:
            endpoint = PairEndpoint.__new__(PairEndpoint)
            endpoint.role, endpoint.broker, endpoint.pending = role, self.broker, None
            endpoint.outgoing = queue.Queue()
            self.broker.endpoints[role] = endpoint
        self.control_frames = json.loads((ROOT / 'analysis/ci/29a9ea7-windows-control.json').read_text())['observations'][0]['native']['room']['frames']
        self.controlled_frames = json.loads((ROOT / 'analysis/ci/4956f9f-windows-controlled-event.json').read_text())['observations'][0]['native']['room']['frames']

    def replay(self, role, frames):
        for frame in frames:
            self.broker.endpoints[role].on_client_frame(frame)

    def test_actual_binary_request_waits_for_its_complete_attachment(self):
        index = next(i for i, frame in enumerate(self.control_frames) if frame.get('text', '').startswith('451-2["control"'))
        self.replay('controller', self.control_frames[index:index + 1])
        target = self.broker.endpoints['controlled']
        self.assertTrue(target.outgoing.empty())
        self.replay('controller', self.control_frames[index + 1:index + 2])
        header, attachment = target.outgoing.get_nowait()
        self.assertTrue(header.startswith(b'451-["be-controlled",'))
        self.assertEqual(attachment, b'\x04ci-control-app-data\x00\xff\xfe')
        self.assertEqual(self.broker.control['ack'], '2')
        self.assertFalse(self.broker.negotiation_observed())

    def test_actual_peer_capability_is_used_in_original_request_ack(self):
        self.replay('controller', self.control_frames)
        capability = next(frame for frame in self.controlled_frames if frame.get('text', '').startswith('42["forward_setting",'))
        self.replay('controlled', [capability])
        wire, = self.broker.endpoints['controller'].outgoing.get_nowait()
        self.assertTrue(wire.startswith(b'432['))
        status, result = json.loads(wire[3:])
        self.assertEqual(status, 'success')
        actual = json.loads(capability['text'][2:])[1]['data']['device_capability']
        self.assertEqual(json.loads(result['streamer_data'])['device_capability'], actual)
        self.assertEqual(result['client_id'], 'ci-controlled')
        self.assertFalse(self.broker.negotiation_observed())

    def test_initial_targetless_guard_is_retained_without_forwarding(self):
        self.replay('controlled', self.controlled_frames[:5])
        self.assertTrue(all(item.outgoing.empty() for item in self.broker.endpoints.values()))
        guards = [item for item in self.broker.events if item['event'] == 'soac']
        self.assertEqual(len(guards), 2)
        self.assertTrue(all(item['attachment_bytes'] == [5808] for item in guards))


if __name__ == '__main__':
    unittest.main()
