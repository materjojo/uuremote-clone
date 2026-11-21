#!/usr/bin/env python3
"""Parent-only evidence checks for original Windows rendered test windows.

No frame is sent by this module. Source colors go only to the controlled child;
the controller child returns samples from its independently rendered window.
"""
import hashlib
import json
from pathlib import Path
import secrets
import struct
import time


ROLES = ('controller', 'controlled')


def matching_colors(observed, expected, tolerance=35):
    if len(observed) != 4 or len(expected) != 4:
        return False
    return all(isinstance(a, int) and 0 <= a <= 0xffffff
               and all(abs(((a >> shift) & 255) - ((b >> shift) & 255)) <= tolerance for shift in (0, 8, 16))
               for a, b in zip(observed, expected))


def bitmap_quarters(data):
    """Read four client-area samples from an uncompressed 32-bit BMP."""
    if len(data) < 54 or data[:2] != b'BM':
        raise ValueError('Missing complete BMP headers')
    file_size, offset, dib_size = struct.unpack_from('<I4xII', data, 2)
    width, signed_height, planes, depth, compression = struct.unpack_from('<iiHHI', data, 18)
    height = abs(signed_height)
    if (file_size != len(data) or dib_size != 40 or offset != 54 or planes != 1 or depth != 32
            or compression != 0 or not 1 <= width <= 4096 or not 1 <= height <= 4096
            or len(data) != offset + width * height * 4):
        raise ValueError('Unexpected or truncated native screen bitmap')
    colors = []
    for index in range(4):
        x = width * (1 if index % 2 == 0 else 3) // 4
        y = height * (1 if index < 2 else 3) // 4
        stored_y = y if signed_height < 0 else height - 1 - y
        blue, green, red, _ = struct.unpack_from('<BBBB', data, offset + (stored_y * width + x) * 4)
        colors.append(red | (green << 8) | (blue << 16))
    return {'width': width, 'height': height, 'colors': colors}


class MediaPixels:
    def __init__(self, workspace, patterns=None):
        self.workspace = Path(workspace)
        self.directory = self.workspace / 'media-samples'
        self.directory.mkdir()
        if patterns is None:
            palette = [(224, 32, 32), (32, 224, 32), (32, 32, 224),
                       (224, 224, 32), (32, 224, 224), (224, 32, 224)]
            secrets.SystemRandom().shuffle(palette)
            first = [red | (green << 8) | (blue << 16) for red, green, blue in palette[:4]]
            patterns = [first, first[1:] + first[:1]]
        self.patterns = patterns
        self.started = time.monotonic()
        self._seen = set()
        self._phase = 0
        self._matches = {}
        self._snapshots = {}
        self.verified = False
        self.report = {'source_patterns_colorref': patterns, 'tolerance': 35, 'phase_matches': [],
                       'snapshots': [], 'pixels_verified': False,
                       'scope': 'Two distinct controlled-window patterns must match controller screen samples and both roles\' actual BMP snapshots.'}

    def settings(self, role):
        settings = {'media': True, 'media_start_path': str(self.workspace / 'media-start'),
                    'media_phase_path': str(self.workspace / 'media-phase-1'),
                    'media_verified_path': str(self.workspace / 'media-verified'),
                    'snapshot_prefix': str(self.workspace / 'snapshot-'),
                    'sample_directory': str(self.directory)}
        if role == 'controlled':
            settings['source_patterns'] = self.patterns
        return settings

    def observe(self):
        if not (self.workspace / 'media-start').exists():
            (self.workspace / 'media-start').write_text('both original binary receivers verified; begin media observation')
        fresh = []
        for path in sorted(self.directory.glob('sample-*.json')):
            if path.name in self._seen:
                continue
            sample = json.loads(path.read_text(encoding='utf-8'))
            self._seen.add(path.name)
            fresh.append(sample)
        phase = self._phase
        if phase not in self._matches:
            for sample in fresh:
                if (sample.get('frame_change_count', 0) > 0
                        and matching_colors(sample.get('colors', []), self.patterns[phase])):
                    record = {'phase': phase, 'sample': sample, 'parent_elapsed_ms': round((time.monotonic() - self.started) * 1000)}
                    self._matches[phase] = record
                    self.report['phase_matches'].append(record)
                    (self.workspace / ('snapshot-' + str(phase))).write_text('retain both native client-area snapshots')
                    break
        if phase not in self._matches:
            return
        for role in ROLES:
            key = role, phase
            if key in self._snapshots:
                continue
            path = self.directory / (role + '-phase-' + str(phase) + '.bmp')
            try:
                data = path.read_bytes()
            except OSError:
                continue  # Child owns an exclusive writer until the BMP is complete.
            snapshot = bitmap_quarters(data)
            if (snapshot['width'], snapshot['height']) != (320, 240):
                raise ValueError('Original window observation changed its client-area size')
            if not matching_colors(snapshot['colors'], self.patterns[phase], 8 if role == 'controlled' else 35):
                raise ValueError('Native ' + role + ' screen snapshot did not preserve source phase ' + str(phase))
            record = {'role': role, 'phase': phase, 'path': str(path.relative_to(self.workspace)),
                      'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(), **snapshot}
            self._snapshots[key] = record
            self.report['snapshots'].append(record)
        if not all((role, phase) in self._snapshots for role in ROLES):
            return
        if phase == 0:
            self._phase = 1
            (self.workspace / 'media-phase-1').write_text('first source and renderer snapshots verified; change only source colors')
        else:
            self.verified = self.report['pixels_verified'] = True
            (self.workspace / 'media-verified').write_text('both distinct source patterns observed in original renderer samples and snapshots')
