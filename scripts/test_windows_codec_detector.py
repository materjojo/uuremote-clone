#!/usr/bin/env python3
"""Report parsing tests; do not load or execute the original Windows target."""
import unittest
from probe_windows_codec_detector import summarize_batch


class DetectorReportTests(unittest.TestCase):
    def test_width_height_precede_the_probe_flag(self):
        report = summarize_batch('RESULT,2,3,10,3840,2160,1\r\nBATCH_DONE\r\n', 0)
        self.assertTrue(report['protocol_completed'])
        self.assertEqual(report['accepted_rows'], [{'codec': 2, 'chroma': 3, 'bitdepth': 10,
                                                  'width': 3840, 'height': 2160, 'probe_flag': 1}])
        self.assertEqual(len(report['positive_probe_rows']), 1)

    def test_batch_completion_does_not_imply_a_positive_probe(self):
        report = summarize_batch('RESULT,1,3,10,0,0,0\nBATCH_DONE\n', 0)
        self.assertTrue(report['protocol_completed'])
        self.assertEqual(len(report['accepted_rows']), 1)
        self.assertEqual(report['positive_probe_rows'], [])

    def test_partial_failed_and_timed_out_batches_discard_candidate_rows(self):
        for tail, exit_code, timed_out in [('', 0, False), ('BATCH_DONE\n', 1, False),
                                            ('BATCH_DONE\n', 0, True)]:
            with self.subTest(tail=tail, exit_code=exit_code, timed_out=timed_out):
                report = summarize_batch('RESULT,1,1,8,1920,1080,1\n' + tail, exit_code, timed_out)
                self.assertEqual(len(report['rows']), 1)
                self.assertFalse(report['protocol_completed'])
                self.assertEqual(report['accepted_rows'], [])
                self.assertEqual(report['positive_probe_rows'], [])

    def test_diagnostics_are_retained_without_becoming_result_rows(self):
        report = summarize_batch('BATCH_DIAG,decoder=32,stage=probe,result=failure\n'
                                 'BATCH_ERROR,failed to init D3D11 for adapter 0\n', 1)
        self.assertEqual(len(report['diagnostics']), 1)
        self.assertEqual(len(report['batch_errors']), 1)
        self.assertEqual(report['rows'], [])
        self.assertFalse(report['protocol_completed'])

    def test_strict_report_validation_rejects_malformed_and_out_of_range_rows(self):
        for line in ['RESULT,1,1,8,1920,1080', 'RESULT,1,1,8,1920,1080,1,extra',
                     'RESULT,1,1,8,2147483648,1080,1', 'RESULT,1,1,8,1920,1080,word']:
            report = summarize_batch(line + '\nBATCH_DONE\n', 0)
            self.assertFalse(report['protocol_completed'])
            self.assertEqual(report['malformed_result_lines'], [line])


if __name__ == '__main__':
    unittest.main()
