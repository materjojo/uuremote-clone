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


def bitmap_pattern(data, expected, tolerance):
    """Check the whole retained client area, including quadrant geometry."""
    layout = bitmap_quarters(data)
    width, height = layout['width'], layout['height']
    signed_height = struct.unpack_from('<i', data, 22)[0]
    palette = [((color >> 16) & 255, (color >> 8) & 255, color & 255) for color in expected]
    view, matched = memoryview(data), 0
    for y in range(height):
        stored_y = y if signed_height < 0 else height - y - 1
        row = 54 + stored_y * width * 4
        for x in range(width):
            color = palette[(0 if y < height // 2 else 2) + (0 if x < width // 2 else 1)]
            index = row + x * 4
            matched += (abs(view[index] - color[0]) <= tolerance
                        and abs(view[index + 1] - color[1]) <= tolerance
                        and abs(view[index + 2] - color[2]) <= tolerance)
    total = width * height
    return {'pattern_pixels': total, 'matching_pattern_pixels': matched,
            'pattern_match_fraction': matched / total, 'pattern_tolerance': tolerance}


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
        self.report = {'source_patterns_colorref': patterns, 'tolerance': 35,
                       'minimum_pattern_match_fraction': 0.97, 'phase_matches': [],
                       'snapshots': [], 'pixels_verified': False,
                       'scope': 'Two distinct controlled-window patterns must match controller screen samples and both roles\' actual BMP snapshots.'}

    def settings(self, role):
        settings = {'media': True, 'media_start_path': str(self.workspace / 'media-start'),
                    'media_phase_path': str(self.workspace / 'media-phase-1'),
                    'media_verified_path': str(self.workspace / 'media-verified'),
                    'snapshot_prefix': str(self.workspace / 'snapshot-'),
                    'sample_directory': str(self.directory),
                    'stats_ready_path': str(self.workspace / (role + '-stats-ready.json'))}
        if role == 'controlled':
            settings['source_patterns'] = self.patterns
        return settings

    @property
    def complete(self):
        return self.verified and all((self.workspace / (role + '-stats-ready.json')).exists() for role in ROLES)

    def verify_stats(self, children):
        try:
            if not self.complete or set(children) != set(ROLES):
                raise ValueError('Both post-render original statistics callbacks are required')
            records = []
            for role in ROLES:
                marker = json.loads((self.workspace / (role + '-stats-ready.json')).read_text(encoding='utf-8'))
                managed = children[role]['managed']
                raw = marker['Json'].encode('utf-8')
                if (marker['Handle'] != managed['handle']
                        or hashlib.sha256(raw).hexdigest() != marker['Sha256']
                        or not managed['media'].get('post_render_stats_received')
                        or not any(item['Handle'] == marker['Handle'] and item['Json'] == marker['Json']
                                   for item in managed['media']['connection_stats'])):
                    raise ValueError('Original statistics marker did not match owned callback bytes')
                records.append({'role': role, 'handle': marker['Handle'], 'bytes': len(raw),
                                'sha256': marker['Sha256'], 'data': json.loads(marker['Json'])})
            self.report['post_render_stats'] = records
            self.report['post_render_stats_bytes_verified'] = True
            return True
        except (OSError, ValueError, KeyError, TypeError) as error:
            self.report['stats_validation_error'] = str(error)
            self.report['post_render_stats_bytes_verified'] = False
            return False

    def observe(self):
        if self.verified:
            return
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
            tolerance = 8 if role == 'controlled' else 35
            if not matching_colors(snapshot['colors'], self.patterns[phase], tolerance):
                raise ValueError('Native ' + role + ' screen snapshot did not preserve source phase ' + str(phase))
            pattern = bitmap_pattern(data, self.patterns[phase], tolerance)
            if pattern['pattern_match_fraction'] < self.report['minimum_pattern_match_fraction']:
                raise ValueError('Native ' + role + ' full-image pattern did not preserve source phase ' + str(phase))
            record = {'role': role, 'phase': phase, 'path': str(path.relative_to(self.workspace)),
                      'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(), **snapshot, **pattern}
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
