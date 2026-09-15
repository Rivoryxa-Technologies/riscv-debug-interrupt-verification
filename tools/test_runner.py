#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("runner", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)

class ClassificationTests(unittest.TestCase):
    def test_timeout_never_passes_even_with_markers(self):
        compile_ok = {"returncode": 0, "timed_out": False}
        timed_out = {"returncode": 124, "timed_out": True,
                     "output": runner.MUTANT_MARKERS["debug_priority_mutant"] + "\nTEST_FAIL"}
        self.assertFalse(runner.classify("debug_priority_mutant", compile_ok, timed_out))

    def test_arbitrary_failure_is_not_negative_control_evidence(self):
        compile_ok = {"returncode": 0, "timed_out": False}
        crash = {"returncode": 1, "timed_out": False, "output": "compiler runtime crash"}
        self.assertFalse(runner.classify("debug_priority_mutant", compile_ok, crash))

    def test_each_mutant_requires_its_own_marker(self):
        compile_ok = {"returncode": 0, "timed_out": False}
        debug_failure = {"returncode": 1, "timed_out": False,
                         "output": "DEBUG_IRQ_PRIORITY_FAILED\nTEST_FAIL"}
        self.assertTrue(runner.classify("debug_priority_mutant", compile_ok, debug_failure))
        self.assertFalse(runner.classify("exception_priority_mutant", compile_ok, debug_failure))

if __name__ == "__main__": unittest.main()
