#!/usr/bin/env python3
"""Check dependency boundaries so platform-only fixes cannot rebuild every app."""
import json
from pathlib import Path
import unittest
from ci_plan import affected, plan, shared_file_targets, TARGETS


class BuildSelectionTests(unittest.TestCase):
    def selected(self, paths):
        return {name for name, value in affected(paths).items() if value}

    def test_docs_and_evidence_do_not_compile_apps(self):
        self.assertEqual(self.selected(['README.md', 'docs/11-native-contract.md',
                                       'analysis/official/android/controller-send-text.json',
                                       'server/rendezvous.py', '.github/workflows/peer-service.yml',
                                       'scripts/ci_plan.py', 'scripts/test_ci_plan.py']), set())

    def test_each_platform_is_isolated(self):
        cases = [('Sources/UURemoteClone/App/AppState.swift', 'macos'),
                 ('Package.swift', 'macos'),
                 ('Tests/OfficialStreamerTests/OfficialStreamerTests.swift', 'macos'),
                 ('platforms/windows/MainWindow.xaml.cs', 'windows'),
                 ('Tests/WindowsOfficialSmoke/Program.cs', 'windows'),
                 ('Tests/WindowsPeerSmoke/Program.cs', 'windows'),
                 ('platforms/android/app/build.gradle', 'android'),
                 ('scripts/verify_android_abi.py', 'android')]
        for path, platform in cases:
            with self.subTest(path=path):
                self.assertEqual(self.selected([path]), {platform})

    def test_shared_native_and_wire_changes_reach_every_consumer(self):
        for path in ['core/src/gvpb.cpp', 'core/tests/test_core.cpp', 'proto/gv_pb/main.proto',
                     'native/official/include/official_streamer_abi.h',
                     'native/official/official_streamer_abi.cpp', '.gitattributes',
                     '.github/workflows/build.yml']:
            with self.subTest(path=path):
                self.assertEqual(self.selected([path]), set(TARGETS))

    def test_runtime_chunks_only_build_their_platform(self):
        for platform in ['macos', 'windows']:
            self.assertEqual(self.selected([f'native/official/runtime-chunks/{platform}/library.part000']), {platform})

    def test_windows_detector_scripts_are_isolated(self):
        for path in ('scripts/probe_windows_codec_detector.py', 'scripts/test_windows_codec_detector.py',
                     'scripts/probe_windows_streamer_lifecycle.py', 'scripts/probe_windows_managed_engine.py',
                     'scripts/probe_windows_streamer_rooms.py', 'Tests/WindowsCodecDetector/CMakeLists.txt'):
            self.assertEqual(self.selected([path]), {'windows'})

    def test_windows_runtime_manifest_addition_does_not_rebuild_other_platforms(self):
        for path, files in [
            ('native/official/manifest.json', [{'platform': 'macos', 'path': 'mac'},
                                             {'platform': 'windows', 'path': 'dll'}]),
            ('native/official/runtime-chunks/index.json', [{'output': 'native/official/runtime/macos/libstreamer.dylib'},
                                                         {'output': 'native/official/runtime/windows/streamer.dll'}])]:
            old = json.dumps({'encoding': 'unchanged', 'files': files})
            added = {'platform': 'windows', 'output': 'native/official/runtime/windows/StreamerCodecDetector.exe'}
            new = json.dumps({'encoding': 'unchanged', 'files': [*files, added]})
            with self.subTest(path=path):
                self.assertEqual(shared_file_targets(path, old, new), {'windows'})
                self.assertEqual(shared_file_targets(path, new, old), {'windows'})
                changed_header = json.dumps({'encoding': 'changed', 'files': files})
                self.assertEqual(shared_file_targets(path, old, changed_header), {'macos', 'windows', 'android'})
                self.assertEqual(shared_file_targets(path, old, '{broken json'), {'macos', 'windows', 'android'})

    def test_windows_workflow_step_does_not_rebuild_other_platforms(self):
        workflow = (Path(__file__).resolve().parents[1] / '.github/workflows/build.yml').read_text()
        updated = workflow.replace('      - name: Publish WPF app with native runtime',
                                   '      - name: Publish Windows app and original detector')
        self.assertNotEqual(workflow, updated)
        self.assertEqual(shared_file_targets('.github/workflows/build.yml', workflow, updated), {'windows'})
        for updated in [workflow.replace('name: build', 'name: changed', 1),
                        workflow.replace('  plan:', '  unknown-job:', 1),
                        workflow.replace('  plan:', '  plan:\n    # changed selection logic', 1)]:
            self.assertEqual(shared_file_targets('.github/workflows/build.yml', workflow, updated), set(TARGETS))

    def test_push_reads_shared_files_from_both_selected_revisions(self):
        seen = []
        path = 'native/official/manifest.json'
        versions = {'before': json.dumps({'files': []}),
                    'after': json.dumps({'files': [{'platform': 'windows', 'path': 'detector'}]})}
        def read(revision, name):
            seen.append((revision, name))
            return versions[revision]
        selected, _ = plan({'before': 'before', 'after': 'after'}, 'push', lambda *_: [path], read)
        self.assertEqual({k for k, v in selected.items() if v}, {'windows'})
        self.assertEqual(seen, [('before', path), ('after', path)])

    def test_multi_platform_change_is_union(self):
        self.assertEqual(self.selected(['platforms/windows/OfficialStreamer.cs', 'platforms/android/app/build.gradle']),
                         {'windows', 'android'})

    def test_manual_target_does_not_read_git_or_build_other_platforms(self):
        def unexpected(*_):
            raise AssertionError('Manual builds must not diff repository history')
        selected, _ = plan({'inputs': {'target': 'windows'}}, 'workflow_dispatch', unexpected)
        self.assertEqual({k for k, v in selected.items() if v}, {'windows'})

    def test_new_branch_validates_all(self):
        selected, _ = plan({'before': '0' * 40, 'after': 'new'}, 'push', lambda *_: [])
        self.assertTrue(all(selected.values()))

    def test_push_uses_entire_before_after_range(self):
        observed = []
        def diff(before, after):
            observed.append((before, after))
            return ['platforms/android/app/src/main/java/Changed.java']
        selected, _ = plan({'before': 'before', 'after': 'after'}, 'push', diff)
        self.assertEqual(observed, [('before', 'after')])
        self.assertEqual({k for k, v in selected.items() if v}, {'android'})


if __name__ == '__main__':
    unittest.main()
