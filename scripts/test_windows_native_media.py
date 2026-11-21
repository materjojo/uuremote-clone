#!/usr/bin/env python3
"""Offline checks of evidence parsing/gates, not original-media execution."""
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
from windows_native_media_observation import MediaPixels, bitmap_pattern, bitmap_quarters, matching_colors


PATTERNS = [[0x2020e0, 0x20e020, 0xe02020, 0x20e0e0],
            [0x20e020, 0xe02020, 0x20e0e0, 0x2020e0]]


def bitmap(colors, bottom_up=False):
    width, height = 320, 240
    pixels = bytearray()
    for stored_y in range(height):
        y = height - stored_y - 1 if bottom_up else stored_y
        for x in range(width):
            color = colors[(0 if y < height // 2 else 2) + (0 if x < width // 2 else 1)]
            pixels.extend(((color >> 16) & 255, (color >> 8) & 255, color & 255, 0))
    header = b'BM' + struct.pack('<IHHI', len(pixels) + 54, 0, 0, 54)
    header += struct.pack('<IiiHHIIiiII', 40, width, height if bottom_up else -height,
                          1, 32, 0, len(pixels), 0, 0, 0, 0)
    return header + pixels


def sample(observer, index, colors, frames=1):
    (observer.directory / ('sample-%04d.json' % index)).write_text(json.dumps(
        {'index': index, 'colors': colors, 'frame_change_count': frames}))


class NativeMediaEvidenceTests(unittest.TestCase):
    def test_bitmap_rgb_order_and_both_vertical_origins(self):
        for bottom in (False, True):
            parsed = bitmap_quarters(bitmap(PATTERNS[0], bottom))
            self.assertEqual((parsed['width'], parsed['height']), (320, 240))
            self.assertEqual(parsed['colors'], PATTERNS[0])
            self.assertEqual(bitmap_pattern(bitmap(PATTERNS[0], bottom), PATTERNS[0], 8)['pattern_match_fraction'], 1.0)

    def test_bitmap_rejects_truncation_wrong_format_and_invalid_color(self):
        image = bitmap(PATTERNS[0])
        compressed = bytearray(image)
        struct.pack_into('<I', compressed, 30, 1)
        for invalid in (b'', image[:53], image[:-4], image + b'x', bytes(compressed)):
            with self.subTest(length=len(invalid)), self.assertRaises(ValueError):
                bitmap_quarters(invalid)
        self.assertFalse(matching_colors([0xffffffff] * 4, PATTERNS[0]))
        self.assertFalse(matching_colors([0x202020] * 4, PATTERNS[0]))

    def test_no_decoded_callback_or_gray_pixels_cannot_advance(self):
        with tempfile.TemporaryDirectory() as directory:
            observer = MediaPixels(directory, PATTERNS)
            self.assertNotIn('source_patterns', observer.settings('controller'))
            self.assertIn('source_patterns', observer.settings('controlled'))
            sample(observer, 0, PATTERNS[0], frames=0)
            sample(observer, 1, [0x202020] * 4)
            observer.observe()
            self.assertFalse(observer.report['phase_matches'])
            self.assertFalse((Path(directory) / 'snapshot-0').exists())
            self.assertFalse(observer.verified)

    def test_both_phases_need_both_roles_actual_snapshots(self):
        with tempfile.TemporaryDirectory() as directory:
            observer = MediaPixels(directory, PATTERNS)
            for phase in range(2):
                sample(observer, phase, PATTERNS[phase])
                observer.observe()
                self.assertFalse(observer.verified)
                self.assertTrue((Path(directory) / ('snapshot-' + str(phase))).exists())
                (observer.directory / ('controlled-phase-%d.bmp' % phase)).write_bytes(bitmap(PATTERNS[phase]))
                observer.observe()
                self.assertFalse(observer.verified)
                (observer.directory / ('controller-phase-%d.bmp' % phase)).write_bytes(bitmap(PATTERNS[phase]))
                observer.observe()
                if phase == 0:
                    self.assertTrue((Path(directory) / 'media-phase-1').exists())
                    self.assertFalse(observer.verified)
            self.assertTrue(observer.verified)
            self.assertEqual(len(observer.report['snapshots']), 4)
            self.assertTrue(all(record['pattern_pixels'] == 76800 and record['pattern_match_fraction'] == 1.0
                                for record in observer.report['snapshots']))
            self.assertTrue((Path(directory) / 'media-verified').exists())
            self.assertFalse(observer.complete)  # Neither process may stop before both actual statistics callbacks.

    def test_sparse_correct_pixels_do_not_replace_whole_rendered_image(self):
        with tempfile.TemporaryDirectory() as directory:
            observer = MediaPixels(directory, PATTERNS)
            sample(observer, 0, PATTERNS[0])
            observer.observe()
            invalid = bytearray(bitmap([0x202020] * 4))
            for index, color in enumerate(PATTERNS[0]):
                x = 320 * (1 if index % 2 == 0 else 3) // 4
                y = 240 * (1 if index < 2 else 3) // 4
                struct.pack_into('<BBBB', invalid, 54 + (y * 320 + x) * 4,
                                 (color >> 16) & 255, (color >> 8) & 255, color & 255, 0)
            self.assertEqual(bitmap_quarters(invalid)['colors'], PATTERNS[0])
            (observer.directory / 'controller-phase-0.bmp').write_bytes(invalid)
            with self.assertRaisesRegex(ValueError, 'full-image pattern'):
                observer.observe()
            self.assertFalse(observer.verified)

    def test_stats_require_callback_bytes_and_their_actual_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            observer = MediaPixels(directory, PATTERNS)
            observer.verified = True  # Isolate the stats gate; pixel gates are exercised above.
            raw = '{"codec":"offline-parser-fixture"}'
            marker = {'Handle': 1, 'Json': raw, 'Sha256': hashlib.sha256(raw.encode()).hexdigest()}
            children = {}
            for role in ('controller', 'controlled'):
                (Path(directory) / (role + '-stats-ready.json')).write_text(json.dumps(marker))
                children[role] = {'managed': {'handle': 1, 'media': {'post_render_stats_received': True, 'connection_stats': []}}}
            self.assertTrue(observer.complete)
            self.assertFalse(observer.verify_stats(children))  # A marker alone is not a received callback.
            for item in children.values():
                item['managed']['media']['connection_stats'] = [{'Handle': 1, 'Json': raw}]
            self.assertTrue(observer.verify_stats(children))
            marker['Sha256'] = '0' * 64
            (Path(directory) / 'controller-stats-ready.json').write_text(json.dumps(marker))
            self.assertFalse(observer.verify_stats(children))

    def test_wrong_snapshot_rejected_even_after_matching_sparse_samples(self):
        with tempfile.TemporaryDirectory() as directory:
            observer = MediaPixels(directory, PATTERNS)
            sample(observer, 0, PATTERNS[0])
            observer.observe()
            (observer.directory / 'controller-phase-0.bmp').write_bytes(bitmap([0x202020] * 4))
            with self.assertRaisesRegex(ValueError, 'controller screen snapshot'):
                observer.observe()
            self.assertFalse(observer.verified)


if __name__ == '__main__':
    unittest.main()
