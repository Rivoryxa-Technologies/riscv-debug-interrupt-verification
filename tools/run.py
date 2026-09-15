#!/usr/bin/env python3
"""Fetch pinned CV32E40P and run controller-level debug/interrupt evidence."""
import argparse, datetime as dt, hashlib, json, math, os, platform, shutil, signal, subprocess, sys, time, uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = "https://github.com/openhwgroup/cv32e40p.git"
REVISION = "6033d2b1be3295ec774d17ac4cf226faacfdeb08"
PASS_MARKER = "TEST_PASS: upstream CV32E40P controller temporal debug/interrupt/exception scenarios verified"
SMOKE_PASS_MARKER = "TEST_PASS: upstream CV32E40P controller debug/interrupt/exception scenarios verified"
FAIL_MARKERS = ("PULSED_DEBUG_RETENTION_FAILED", "STALLED_FETCH_FAULT_PRIORITY_FAILED",
                "EXCEPTION_FLUSH_DEBUG_FAILED", "DRET_STALL_FAILED", "DRET_REHALT_PRIORITY_FAILED", "SINGLE_STEP_FAILED",
                "BOOT_STATE_TIMEOUT",
                "STATE_TIMEOUT", "TEST_TIMEOUT", "TEST_FAIL")
MUTANT_MARKERS = {"stalled_debug_pulse_mutant": "PULSED_DEBUG_RETENTION_FAILED",
                  "fetch_valid_coupling_mutant": "STALLED_FETCH_FAULT_PRIORITY_FAILED",
                  "exception_flush_debug_mutant": "EXCEPTION_FLUSH_DEBUG_FAILED",
                  "dret_rehalt_mutant": "DRET_REHALT_PRIORITY_FAILED"}
MUTATIONS = {
    "stalled_debug_pulse_mutant": (
        "if( debug_req_i )",
        "if( debug_req_i && instr_valid_i )",
        "incorrectly qualifies the sticky halt-request latch with instruction validity",
    ),
    "fetch_valid_coupling_mutant": (
        "else if (is_fetch_failed_i)\n          begin",
        "else if (is_fetch_failed_i && instr_valid_i)\n          begin",
        "incorrectly qualifies a fetch-fault indication with decode instruction validity",
    ),
    "exception_flush_debug_mutant": (
        "if( debug_req_i )",
        "if( debug_req_i && ctrl_fsm_cs != FLUSH_WB )",
        "incorrectly drops a halt pulse sampled during exception FLUSH_WB",
    ),
    "dret_rehalt_mutant": (
        "if( debug_req_i )",
        "if( debug_req_i && !debug_mode_q )",
        "incorrectly rejects a new halt pulse sampled as DRET clears debug mode",
    ),
}
SMOKE_FAIL_MARKERS = ("DEBUG_IRQ_PRIORITY_FAILED", "IRQ_MASK_IN_DEBUG_FAILED", "DEBUG_ENTRY_FAILED",
                      "DEBUG_RESUME_FAILED", "PENDING_IRQ_AFTER_RESUME_FAILED", "SINGLE_STEP_FAILED",
                      "EXCEPTION_IRQ_PRIORITY_FAILED", "EXCEPTION_TRAP_OUTPUT_FAILED",
                      "STATE_TIMEOUT", "TEST_TIMEOUT", "TEST_FAIL")

def run(command, timeout, cwd=ROOT):
    start = time.monotonic()
    try:
        p = subprocess.Popen(command, cwd=str(cwd), text=True, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, start_new_session=(os.name == "posix"))
        try:
            out, _ = p.communicate(timeout=timeout); code = p.returncode; timed_out = False
        except subprocess.TimeoutExpired as exc:
            os.killpg(p.pid, signal.SIGKILL) if os.name == "posix" else p.kill()
            rest, _ = p.communicate(); partial = exc.stdout or ""
            if isinstance(partial, bytes): partial = partial.decode(errors="replace")
            out = (rest or partial) + "\nRUNNER_TIMEOUT\n"; code = 124; timed_out = True
    except OSError as exc:
        out = "RUNNER_EXEC_ERROR: %s\n" % exc; code = 127; timed_out = False
    return {"command": command, "returncode": code, "timed_out": timed_out,
            "seconds": round(time.monotonic()-start, 6), "output": out}

def sha256(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def classify(name, compiled, simulated, smoke_compiled, smoke_simulated):
    completed = (compiled["returncode"] == 0 and not compiled["timed_out"] and
                 not simulated["timed_out"] and smoke_compiled["returncode"] == 0 and
                 not smoke_compiled["timed_out"] and not smoke_simulated["timed_out"])
    if not completed: return False
    smoke_output = smoke_simulated["output"]
    smoke_ok = (smoke_simulated["returncode"] == 0 and
                smoke_output.count(SMOKE_PASS_MARKER) == 1 and
                not any(x in smoke_output for x in SMOKE_FAIL_MARKERS))
    if not smoke_ok: return False
    output = simulated["output"]
    if name == "correct":
        return (simulated["returncode"] == 0 and output.count(PASS_MARKER) == 1 and
                not any(x in output for x in FAIL_MARKERS))
    marker = MUTANT_MARKERS.get(name)
    unrelated = tuple(x for x in FAIL_MARKERS if x not in (marker, "TEST_FAIL"))
    return (marker is not None and simulated["returncode"] != 0 and
            output.count(marker) == 1 and output.count("TEST_FAIL") == 1 and
            PASS_MARKER not in output and not any(x in output for x in unrelated))

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--timeout", type=float, default=120.0)
    ap.add_argument("--source", type=Path, help="use an existing exact-revision CV32E40P checkout")
    ap.add_argument("--evidence-dir", type=Path,
                    help="write evidence to this new directory instead of a unique runs/ directory")
    args = ap.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0: ap.error("--timeout must be positive and finite")
    missing = [x for x in ("git", "verilator") if not shutil.which(x)]
    if missing: print("ERROR: missing tools: " + ", ".join(missing), file=sys.stderr); return 2
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    evidence = args.evidence_dir.resolve() if args.evidence_dir else ROOT/"runs"/(stamp+"-"+uuid.uuid4().hex[:8])
    try:
        evidence.mkdir(parents=True, exist_ok=False)
    except FileExistsError:
        ap.error("--evidence-dir must name a directory that does not exist")
    source = args.source.resolve() if args.source else ROOT/"third_party"/"cv32e40p"
    steps = []
    if not source.exists():
        source.parent.mkdir(parents=True, exist_ok=True)
        steps.append(run(["git", "clone", "--filter=blob:none", UPSTREAM, str(source)], args.timeout))
        if source.exists():
            steps.append(run(["git", "checkout", "--detach", REVISION], args.timeout, source))
    rev = run(["git", "rev-parse", "HEAD"], 5, source) if source.exists() else {"returncode":127,"output":"","timed_out":False,"seconds":0,"command":[]}
    steps.append(rev)
    clean = run(["git", "status", "--porcelain", "--untracked-files=no"], 5, source) if source.exists() else rev
    steps.append(clean)
    steps_ok = all(x["returncode"] == 0 and not x["timed_out"] for x in steps)
    source_ok = steps_ok and rev["output"].strip() == REVISION and not clean["output"].strip()
    variants = []
    for name in ("correct", *MUTATIONS):
        obj = evidence/("obj_"+name)
        controller = source/"rtl/cv32e40p_controller.sv"
        variant_source_ok = source_ok
        mutation_description = None
        if name != "correct" and source_ok:
            mutant = evidence/("cv32e40p_controller_"+name+".sv")
            original = controller.read_text()
            needle, replacement, mutation_description = MUTATIONS[name]
            if original.count(needle) != 1:
                variant_source_ok = False
            changed = original.replace(needle, replacement, 1)
            if changed == original: variant_source_ok = False
            mutant.write_text(changed); controller = mutant
        compile_cmd = ["verilator", "--binary", "--timing", "-Wno-fatal", "--top-module", "controller_debug_irq_tb", "-Mdir", str(obj),
                       str(source/"rtl/include/cv32e40p_pkg.sv"), str(controller), str(ROOT/"tb/controller_debug_irq_tb.sv")]
        compiled = run(compile_cmd, args.timeout) if variant_source_ok else {"command":compile_cmd,"returncode":125,"timed_out":False,"seconds":0,"output":"SOURCE_REVISION_CLEANLINESS_OR_MUTATION_MATCH_FAILED\n"}
        binary = obj/"Vcontroller_debug_irq_tb"
        simulated = run([str(binary)], args.timeout) if compiled["returncode"] == 0 else {"command":[str(binary)],"returncode":125,"timed_out":False,"seconds":0,"output":"COMPILE_FAILED\n"}
        smoke_obj = evidence/("obj_smoke_"+name)
        smoke_compile_cmd = ["verilator", "--binary", "--timing", "-Wno-fatal", "--top-module", "controller_debug_irq_tb", "-Mdir", str(smoke_obj),
                             str(source/"rtl/include/cv32e40p_pkg.sv"), str(controller), str(ROOT/"tb/controller_debug_irq_smoke_tb.sv")]
        smoke_compiled = run(smoke_compile_cmd, args.timeout) if variant_source_ok else {"command":smoke_compile_cmd,"returncode":125,"timed_out":False,"seconds":0,"output":"SOURCE_REVISION_CLEANLINESS_OR_MUTATION_MATCH_FAILED\n"}
        smoke_binary = smoke_obj/"Vcontroller_debug_irq_tb"
        smoke_simulated = run([str(smoke_binary)], args.timeout) if smoke_compiled["returncode"] == 0 else {"command":[str(smoke_binary)],"returncode":125,"timed_out":False,"seconds":0,"output":"COMPILE_FAILED\n"}
        (evidence/(name+"-compile.log")).write_text(compiled["output"])
        (evidence/(name+"-simulation.log")).write_text(simulated["output"])
        (evidence/(name+"-smoke-compile.log")).write_text(smoke_compiled["output"])
        (evidence/(name+"-smoke-simulation.log")).write_text(smoke_simulated["output"])
        expected = classify(name, compiled, simulated, smoke_compiled, smoke_simulated)
        artifact_paths = {
            "temporal_compile_log": evidence/(name+"-compile.log"),
            "temporal_simulation_log": evidence/(name+"-simulation.log"),
            "ordinary_smoke_compile_log": evidence/(name+"-smoke-compile.log"),
            "ordinary_smoke_simulation_log": evidence/(name+"-smoke-simulation.log"),
        }
        if name != "correct": artifact_paths["generated_mutant"] = controller
        variants.append({"name":name,"synthetic_mutation":mutation_description,
                         "compile":{k:v for k,v in compiled.items() if k != "output"},
                         "simulation":{k:v for k,v in simulated.items() if k != "output"},
                         "ordinary_smoke_compile":{k:v for k,v in smoke_compiled.items() if k != "output"},
                         "ordinary_smoke_simulation":{k:v for k,v in smoke_simulated.items() if k != "output"},
                         "artifact_sha256":{k:sha256(v) for k,v in artifact_paths.items()},
                         "expected_outcome":expected})
    (evidence/"setup.log").write_text("\n".join(x["output"] for x in steps))
    ok = source_ok and all(x["expected_outcome"] for x in variants)
    summary = {"schema_version":1,"run_id":evidence.name,"upstream_url":UPSTREAM,"upstream_revision":REVISION,
               "observed_revision":rev["output"].strip(),"source_revision_match":source_ok,
               "scope":"cv32e40p_controller module-level temporal interactions among debug retention, decode stalls, qualified interrupts, fetch faults, and DRET",
               "scenarios":[
                   "one-cycle debug request retained across invalid/stalled DECODE, then prioritized over a later qualified interrupt",
                   "fetch fault during invalid/stalled DECODE prioritized over a simultaneous qualified interrupt",
                   "halt request sampled during fetch-fault FLUSH_WB retained without disturbing redirect, then prioritized over held interrupt",
                   "DRET held by id_ready_i stall, followed by halt pulse at XRET_JUMP and re-entry before a held interrupt",
                   "single-step debug-cause sanity path",
                   "prior three-scenario smoke bench, including ordinary DRET followed by held-interrupt service, applied to correct RTL and every mutant",
               ],
               "assumptions":["single shared gated/ungated clock","pipeline stage validity is directly driven at the controller boundary","level-held qualified interrupt models pending outside controller","fetch-failed input remains asserted through FLUSH_WB and models detection outside controller","default COREV_PULP=0, COREV_CLUSTER=0, FPU=0"],
               "python":platform.python_version(),"platform":platform.platform(),
               "verilator":run(["verilator","--version"],5)["output"].splitlines()[0],"timeout_seconds":args.timeout,
               "source_sha256":{"cv32e40p_controller.sv":sha256(source/"rtl/cv32e40p_controller.sv") if source_ok else None,
                                "cv32e40p_pkg.sv":sha256(source/"rtl/include/cv32e40p_pkg.sv") if source_ok else None,
                                "controller_debug_irq_tb.sv":sha256(ROOT/"tb/controller_debug_irq_tb.sv"),
                                "controller_debug_irq_smoke_tb.sv":sha256(ROOT/"tb/controller_debug_irq_smoke_tb.sv"),
                                "tools/run.py":sha256(ROOT/"tools/run.py")},
               "setup_steps":[{k:v for k,v in x.items() if k != "output"} for x in steps],
               "variants":variants,"pass_marker":PASS_MARKER,"ordinary_smoke_pass_marker":SMOKE_PASS_MARKER,
               "mutant_failure_markers":MUTANT_MARKERS,"overall_pass":ok}
    (evidence/"summary.json").write_text(json.dumps(summary,indent=2)+"\n")
    if not args.evidence_dir:
        (ROOT/"runs/LATEST").write_text(evidence.name+"\n")
    for variant in variants: print(("PASS" if variant["expected_outcome"] else "FAIL")+": "+variant["name"])
    print("SUMMARY: %s" % ("PASS" if ok else "FAIL")); print("EVIDENCE: %s" % (evidence/"summary.json"))
    return 0 if ok else 1

if __name__ == "__main__": sys.exit(main())
