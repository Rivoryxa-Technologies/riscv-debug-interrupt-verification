#!/usr/bin/env python3
"""Fetch pinned CV32E40P and run controller-level debug/interrupt evidence."""
import argparse, datetime as dt, hashlib, json, math, os, platform, shutil, signal, subprocess, sys, time, uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = "https://github.com/openhwgroup/cv32e40p.git"
REVISION = "6033d2b1be3295ec774d17ac4cf226faacfdeb08"
PASS_MARKER = "TEST_PASS: upstream CV32E40P controller debug/interrupt/exception scenarios verified"
FAIL_MARKERS = ("DEBUG_IRQ_PRIORITY_FAILED", "IRQ_MASK_IN_DEBUG_FAILED", "DEBUG_ENTRY_FAILED",
                "DEBUG_RESUME_FAILED", "PENDING_IRQ_AFTER_RESUME_FAILED", "SINGLE_STEP_FAILED",
                "EXCEPTION_IRQ_PRIORITY_FAILED", "EXCEPTION_TRAP_OUTPUT_FAILED",
                "STATE_TIMEOUT", "TEST_TIMEOUT", "TEST_FAIL")
MUTANT_MARKERS = {"debug_priority_mutant": "DEBUG_IRQ_PRIORITY_FAILED",
                  "exception_priority_mutant": "EXCEPTION_IRQ_PRIORITY_FAILED"}

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

def classify(name, compiled, simulated):
    completed = compiled["returncode"] == 0 and not compiled["timed_out"] and not simulated["timed_out"]
    if not completed: return False
    if name == "correct":
        return simulated["returncode"] == 0 and PASS_MARKER in simulated["output"] and not any(x in simulated["output"] for x in FAIL_MARKERS)
    marker = MUTANT_MARKERS.get(name)
    return marker is not None and simulated["returncode"] != 0 and marker in simulated["output"] and "TEST_FAIL" in simulated["output"] and PASS_MARKER not in simulated["output"]

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--timeout", type=float, default=120.0)
    ap.add_argument("--source", type=Path, help="use an existing exact-revision CV32E40P checkout")
    args = ap.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0: ap.error("--timeout must be positive and finite")
    missing = [x for x in ("git", "verilator") if not shutil.which(x)]
    if missing: print("ERROR: missing tools: " + ", ".join(missing), file=sys.stderr); return 2
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    evidence = ROOT/"runs"/(stamp+"-"+uuid.uuid4().hex[:8]); evidence.mkdir(parents=True)
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
    for name in ("correct", "debug_priority_mutant", "exception_priority_mutant"):
        obj = evidence/("obj_"+name)
        controller = source/"rtl/cv32e40p_controller.sv"
        if name != "correct" and source_ok:
            mutant = evidence/("cv32e40p_controller_"+name+".sv")
            original = controller.read_text()
            if name == "debug_priority_mutant":
                needle = "if ( (debug_req_pending || trigger_match_i) & ~debug_mode_q )"
                replacement = "if ( 1'b0 && (debug_req_pending || trigger_match_i) & ~debug_mode_q )"
            else:
                needle = "else if (is_fetch_failed_i)"
                replacement = "else if (1'b0 && is_fetch_failed_i)"
            changed = original.replace(needle, replacement, 1)
            if changed == original: source_ok = False
            mutant.write_text(changed); controller = mutant
        compile_cmd = ["verilator", "--binary", "--timing", "-Wno-fatal", "--top-module", "controller_debug_irq_tb", "-Mdir", str(obj),
                       str(source/"rtl/include/cv32e40p_pkg.sv"), str(controller), str(ROOT/"tb/controller_debug_irq_tb.sv")]
        compiled = run(compile_cmd, args.timeout) if source_ok else {"command":compile_cmd,"returncode":125,"timed_out":False,"seconds":0,"output":"SOURCE_REVISION_OR_CLEANLINESS_CHECK_FAILED\n"}
        binary = obj/"Vcontroller_debug_irq_tb"
        simulated = run([str(binary)], args.timeout) if compiled["returncode"] == 0 else {"command":[str(binary)],"returncode":125,"timed_out":False,"seconds":0,"output":"COMPILE_FAILED\n"}
        (evidence/(name+"-compile.log")).write_text(compiled["output"])
        (evidence/(name+"-simulation.log")).write_text(simulated["output"])
        expected = classify(name, compiled, simulated)
        variants.append({"name":name,"compile":{k:v for k,v in compiled.items() if k != "output"},"simulation":{k:v for k,v in simulated.items() if k != "output"},"expected_outcome":expected})
    (evidence/"setup.log").write_text("\n".join(x["output"] for x in steps))
    ok = source_ok and all(x["expected_outcome"] for x in variants)
    summary = {"schema_version":1,"run_id":evidence.name,"upstream_url":UPSTREAM,"upstream_revision":REVISION,
               "observed_revision":rev["output"].strip(),"source_revision_match":source_ok,
               "scope":"cv32e40p_controller module-level debug, qualified-interrupt, and instruction-fetch-exception simulation","assumptions":["single shared gated/ungated clock","always-ready simplified pipeline inputs","level-held qualified interrupt models pending outside controller","fetch-failed input models an instruction access fault already detected outside controller","default COREV_PULP=0, COREV_CLUSTER=0, FPU=0"],
               "python":platform.python_version(),"platform":platform.platform(),
               "verilator":run(["verilator","--version"],5)["output"].splitlines()[0],"timeout_seconds":args.timeout,
               "source_sha256":{"cv32e40p_controller.sv":sha256(source/"rtl/cv32e40p_controller.sv") if source_ok else None,
                                "cv32e40p_pkg.sv":sha256(source/"rtl/include/cv32e40p_pkg.sv") if source_ok else None,
                                "controller_debug_irq_tb.sv":sha256(ROOT/"tb/controller_debug_irq_tb.sv"),
                                "tools/run.py":sha256(ROOT/"tools/run.py")},
               "setup_steps":[{k:v for k,v in x.items() if k != "output"} for x in steps],
               "variants":variants,"pass_marker":PASS_MARKER,"mutant_failure_markers":MUTANT_MARKERS,"overall_pass":ok}
    (evidence/"summary.json").write_text(json.dumps(summary,indent=2)+"\n")
    (ROOT/"runs/LATEST").write_text(evidence.name+"\n")
    for variant in variants: print(("PASS" if variant["expected_outcome"] else "FAIL")+": "+variant["name"])
    print("SUMMARY: %s" % ("PASS" if ok else "FAIL")); print("EVIDENCE: %s" % (evidence/"summary.json"))
    return 0 if ok else 1

if __name__ == "__main__": sys.exit(main())
