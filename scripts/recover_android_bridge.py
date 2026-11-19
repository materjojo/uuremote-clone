#!/usr/bin/env python3
"""Recover the selected 4.48.1 Java/JNI glue; never compile or execute the APK.

Input: JADX 1.5.3 sources/com/remote/streamer. The original DEX prototypes are
retained separately under analysis/official/android and checked against javap in CI.
Only dependency/compiler scaffolding is adapted; native names, instance dispatch,
getter descriptors and native callback names are preserved.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SELECTED = [
    'controller/AndroidStreamerController.java', 'controller/StreamerController.java',
    'controlled/AndroidStreamerControlled.java', 'controlled/StreamerControlled.java',
    *('model/' + n + '.java' for n in [
        'AudioCaptureConfig', 'AudioRendererConfig', 'VideoCaptureConfig',
        'VideoRendererConfig', 'IceNetworkConfig', 'StreamerRoomConfig', 'NewControlInfo',
        'StreamerAudioCaptureTarget', 'StreamerChromaSampling', 'StreamerCodecType',
        'StreamerFrameQuality', 'StreamerScreenSourceType', 'StreamerVideoCaptureTarget']),
    * (n + '.java' for n in ['StreamerSurfaceView', 'StreamerSurfaceTexture',
        'StreamerDisplayListener', 'StreamerMediaProjectionCallback', 'StreamerVirtualDisplayCallback']),
]


def remove_block(text, start):
    brace = text.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[:start] + text[end:]


def adapt(src, relative):
    text = src
    # Kotlin's DefaultImpls and mask constructors have no native entry points.
    while (match := re.search(r'    public static final class (?:DefaultImpls|Companion)\b', text)):
        text = remove_block(text, match.start())
    while (match := re.search(r'    public /\* synthetic \*/', text)):
        text = remove_block(text, match.start())
    text = re.sub(r'^import (?:le\.|Wd\.|com.tencent\.).*\n', '', text, flags=re.M)
    text = re.sub(r'^    public static final Companion Companion = .*\n', '', text, flags=re.M)
    text = re.sub(r'^    /\*.*?\*/\n', '', text, flags=re.M)
    text = re.sub(r'/\* compiled from:.*?\*/\n|/\* loaded from:.*?\*/\n', '', text)
    text = re.sub(r'AbstractC2698k\.e\((\w+), "([^"]+)"\);',
                  r'java.util.Objects.requireNonNull(\1, "\2");', text)
    # Kotlin can emit finalize()I; Java source conflicts with Object.finalize()V.
    # This is a non-native convenience wrapper. Finalize()I stays untouched.
    text = re.sub(r'\bint finalize\(\)', 'int shutdown()', text)
    text = text.replace('private Delegate delegate;', 'private volatile Delegate delegate;')
    # Optional callback implementations. JNI calls the preserved outer On* methods.
    if relative in ('controller/StreamerController.java', 'controlled/StreamerControlled.java'):
        start = text.index('    public interface Delegate {')
        end = text.index('\n    }', start)
        block = text[start:end]
        block = re.sub(r'(?m)^(        )void (.*);$', r'\1default void \2 {}', block)
        text = text[:start] + block + text[end:]
    if relative.endswith('AndroidStreamerController.java') or relative.endswith('AndroidStreamerControlled.java'):
        match = re.search(r'public final class \w+ extends \w+ \{', text)
        text = text[:match.end()] + '\n    static { com.remote.streamer.OfficialLibraries.load(); }\n' + text[match.end():]
    if relative == 'model/VideoCaptureConfig.java':
        text = text.replace('this(0, 0, false, 0, 0, 0, 0, 0, 0, false, null, 0, 0, 0, 0, 32767, null);',
                            'this(0, 0, false, 0, 0, 1, 2, 0, 0, false, null, 0, 0, 0, 0);')
    if re.search(r'\b(?:AbstractC269\w*|WXMediaMessage|Wd\.|Companion)\b', text):
        raise ValueError('Unresolved compiler dependency in ' + relative)
    text = '\n'.join(line.rstrip() for line in text.splitlines())
    return '// Recovered from the supplied 4.48.1 APK; see analysis/official/android.\n' + text.strip() + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    args = parser.parse_args()
    dest = ROOT / 'platforms/android/app/src/main/java/com/remote/streamer'
    records = []
    for relative in SELECTED:
        raw = (args.source / relative).read_bytes()
        result = adapt(raw.decode(), relative)
        output = dest / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(result)
        records.append({'path': relative, 'jadx_source_sha256': hashlib.sha256(raw).hexdigest(),
                        'adapted_sha256': hashlib.sha256(result.encode()).hexdigest()})
    manifest = {
        'apk_sha256': '19252db1dd384f25db000b334e6f77616b9dfa26b2e416ce5383038e973e219f',
        'decompiler': 'JADX 1.5.3',
        'coverage': 'selected Java JNI glue only; not application, WebRTC audio or all DEX code',
        'adaptations': ['remove Kotlin synthetic mask constructors and DefaultImpls',
                        'replace Kotlin null checks with Objects.requireNonNull',
                        'rename non-native finalize()I convenience wrapper to shutdown()I',
                        'optional Java default delegate methods, volatile delegate publication',
                        'load the supplied native libraries on first use'],
        'files': records,
    }
    (ROOT / 'analysis/official/android/recovery-manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(f'Recovered {len(records)} Java files; native descriptors will be checked in Actions.')


if __name__ == '__main__':
    main()
