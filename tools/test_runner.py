#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("runner", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)

COMPILE_OK = {"returncode": 0, "timed_out": False}

def smoke_ok(output=None):
    return {"returncode": 0, "timed_out": False,
            "output": output or runner.SMOKE_PASS_MARKER}

def mutant_failure(name, extra=""):
    output = runner.MUTANT_MARKERS[name] + "\nTEST_FAIL"
    if extra: output += "\n" + extra
    return {"returncode": 1, "timed_out": False, "output": output}

def boundary_result(case_id, expected):
    if expected == "pass":
        output = "BOUNDARY_EXERCISE: %s details\nBOUNDARY_CASE_PASS: %s outcome=ok" % (case_id, case_id)
        code = 0
    else:
        output = "BOUNDARY_CASE_FAILED_%s: target\nTEST_FAIL" % case_id
        code = 1
    return {"scenario_id":case_id, "run":{"returncode":code, "timed_out":False, "output":output}}

class ClassificationTests(unittest.TestCase):
    def classify(self, name, simulated, smoke=None, compiled=COMPILE_OK, smoke_compiled=COMPILE_OK):
        return runner.classify(name, compiled, simulated, smoke_compiled, smoke or smoke_ok())

    def test_exact_mutant_diagnostic_and_smoke_pass_are_accepted(self):
        name = "stalled_debug_pulse_mutant"
        self.assertTrue(self.classify(name, mutant_failure(name)))

    def test_timeout_and_arbitrary_failure_are_rejected(self):
        name = "stalled_debug_pulse_mutant"
        timed_out = {"returncode": 124, "timed_out": True,
                     "output": runner.MUTANT_MARKERS[name] + "\nTEST_FAIL"}
        crash = {"returncode": 1, "timed_out": False, "output": "runtime crash"}
        self.assertFalse(self.classify(name, timed_out))
        self.assertFalse(self.classify(name, crash))

    def test_wrong_or_unrelated_diagnostic_is_rejected(self):
        name = "stalled_debug_pulse_mutant"
        wrong = mutant_failure("fetch_valid_coupling_mutant")
        cascaded = mutant_failure(name, runner.MUTANT_MARKERS["exception_flush_debug_mutant"])
        self.assertFalse(self.classify(name, wrong))
        self.assertFalse(self.classify(name, cascaded))

    def test_duplicate_diagnostic_or_test_fail_is_rejected(self):
        name = "dret_rehalt_mutant"
        marker = runner.MUTANT_MARKERS[name]
        duplicate_marker = {"returncode": 1, "timed_out": False,
                            "output": marker + "\n" + marker + "\nTEST_FAIL"}
        duplicate_fail = {"returncode": 1, "timed_out": False,
                          "output": marker + "\nTEST_FAIL\nTEST_FAIL"}
        self.assertFalse(self.classify(name, duplicate_marker))
        self.assertFalse(self.classify(name, duplicate_fail))

    def test_smoke_failure_or_duplicate_pass_is_rejected(self):
        name = "fetch_valid_coupling_mutant"
        failed_smoke = {"returncode": 1, "timed_out": False,
                        "output": "PENDING_IRQ_AFTER_RESUME_FAILED\nTEST_FAIL"}
        duplicate_pass = smoke_ok(runner.SMOKE_PASS_MARKER + "\n" + runner.SMOKE_PASS_MARKER)
        self.assertFalse(self.classify(name, mutant_failure(name), failed_smoke))
        self.assertFalse(self.classify(name, mutant_failure(name), duplicate_pass))

    def test_correct_requires_one_pass_marker_and_no_diagnostic(self):
        good = {"returncode": 0, "timed_out": False, "output": runner.PASS_MARKER}
        duplicate = {"returncode": 0, "timed_out": False,
                     "output": runner.PASS_MARKER + "\n" + runner.PASS_MARKER}
        diagnostic = {"returncode": 0, "timed_out": False,
                      "output": runner.PASS_MARKER + "\nDRET_STALL_FAILED"}
        self.assertTrue(self.classify("correct", good))
        self.assertFalse(self.classify("correct", duplicate))
        self.assertFalse(self.classify("correct", diagnostic))

    def test_success_exit_and_unknown_variant_are_rejected(self):
        name = "dret_rehalt_mutant"
        success = {"returncode": 0, "timed_out": False,
                   "output": runner.MUTANT_MARKERS[name] + "\nTEST_FAIL"}
        unknown = {"returncode": 1, "timed_out": False, "output": "TEST_FAIL"}
        self.assertFalse(self.classify(name, success))
        self.assertFalse(self.classify("unknown", unknown))

    def test_boundary_matrix_requires_complete_unique_cases(self):
        expected = runner.BOUNDARY_EXPECTATIONS["correct"]
        results = [boundary_result(case_id, outcome) for case_id, outcome in expected.items()]
        self.assertTrue(runner.classify_boundary("correct", COMPILE_OK, results))
        self.assertFalse(runner.classify_boundary("correct", COMPILE_OK, results[:-1]))
        self.assertFalse(runner.classify_boundary("correct", COMPILE_OK, results[:-1] + [results[0]]))

    def test_boundary_target_rejects_pass_or_unrelated_failure(self):
        name = "dret_rehalt_mutant"
        expected = runner.BOUNDARY_EXPECTATIONS[name]
        results = [boundary_result(case_id, outcome) for case_id, outcome in expected.items()]
        self.assertTrue(runner.classify_boundary(name, COMPILE_OK, results))
        target = next(x for x in results if x["scenario_id"] == "XRET_DURING")
        target["run"] = {"returncode":1, "timed_out":False,
                         "output":"BOUNDARY_CASE_FAILED_FLUSH_DURING: wrong\nTEST_FAIL"}
        self.assertFalse(runner.classify_boundary(name, COMPILE_OK, results))

    def test_boundary_metadata_is_complete(self):
        required = {"pulse_position", "stall_length", "sampled_request", "eventual_service_order"}
        self.assertEqual(len(runner.BOUNDARY_CASES), len(set(runner.BOUNDARY_CASES)))
        for metadata in runner.BOUNDARY_CASES.values():
            self.assertEqual(required, set(metadata))

if __name__ == "__main__": unittest.main()
