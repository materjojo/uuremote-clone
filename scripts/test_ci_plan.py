#!/usr/bin/env python3
"""Check dependency boundaries so platform-only fixes cannot rebuild every app."""
import unittest
from ci_plan import affected, plan, TARGETS


class BuildSelectionTests(unittest.TestCase):
    def selected(self, paths):
        return {name for name, value in affected(paths).items() if value}

    def test_docs_and_evidence_do_not_compile_apps(self):
        self.assertEqual(self.selected(['README.md', 'docs/11-native-contract.md',
                                       'analysis/official/android/controller-send-text.json']), set())

    def test_each_platform_is_isolated(self):
        cases = [('Sources/UURemoteClone/App/AppState.swift', 'macos'),
                 ('Package.swift', 'macos'),
                 ('Tests/OfficialStreamerTests/OfficialStreamerTests.swift', 'macos'),
                 ('platforms/windows/MainWindow.xaml.cs', 'windows'),
                 ('Tests/WindowsOfficialSmoke/Program.cs', 'windows'),
                 ('platforms/android/app/build.gradle', 'android'),
                 ('scripts/verify_android_abi.py', 'android')]
        for path, platform in cases:
            with self.subTest(path=path):
                self.assertEqual(self.selected([path]), {platform})

    def test_shared_native_and_wire_changes_reach_every_consumer(self):
        for path in ['core/src/gvpb.cpp', 'core/tests/test_core.cpp', 'proto/gv_pb/main.proto',
                     'native/official/include/official_streamer_abi.h',
                     'native/official/official_streamer_abi.cpp', '.gitattributes',
                     '.github/workflows/build.yml', 'scripts/ci_plan.py']:
            with self.subTest(path=path):
                self.assertEqual(self.selected([path]), set(TARGETS))

    def test_runtime_chunks_only_build_their_platform(self):
        for platform in ['macos', 'windows']:
            self.assertEqual(self.selected([f'native/official/runtime-chunks/{platform}/library.part000']), {platform})

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
