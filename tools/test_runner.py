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
                     "output": runner.MUTANT_MARKER + "\nTEST_FAIL"}
        self.assertFalse(runner.classify("mutant", compile_ok, timed_out))

    def test_arbitrary_failure_is_not_negative_control_evidence(self):
        compile_ok = {"returncode": 0, "timed_out": False}
        crash = {"returncode": 1, "timed_out": False, "output": "compiler runtime crash"}
        self.assertFalse(runner.classify("mutant", compile_ok, crash))

if __name__ == "__main__": unittest.main()
