# RISC-V Debug, Interrupt, and Exception Controller Evidence

This repository runs focused behavioral checks against the real OpenHW Group CV32E40P controller. It fetches immutable upstream commit `6033d2b1be3295ec774d17ac4cf226faacfdeb08`; the upstream RTL is never patched in place.

## What is executed

The SystemVerilog bench instantiates `cv32e40p_controller` and drives its real FSM through three scenarios:

1. A qualified interrupt request and external debug halt request arrive together in `DECODE`. The controller takes debug priority, records `DBG_CAUSE_HALTREQ`, enters halted debug mode, and does not acknowledge the interrupt while halted. The bench then drives the real DRET pipeline sequence through `FLUSH_EX`, `FLUSH_WB`, and `XRET_JUMP`, observes the restore strobe, and verifies return to running mode. The still-held qualified interrupt is acknowledged after resume, then the bench drops it to model masking on trap entry.
2. A fresh boot with single-step enabled reaches `DBG_TAKEN_IF`, records `DBG_CAUSE_STEP`, and enters halted debug mode.
3. An instruction-fetch fault and qualified interrupt request arrive together in `DECODE`. The controller gives the exception priority, saves the instruction-fault cause, does not acknowledge the interrupt, enters `FLUSH_WB`, and selects the exception redirect.

The runner also builds two generated negative-control copies in the evidence directory. One disables the controller's first debug-priority condition and must fail with `DEBUG_IRQ_PRIORITY_FAILED`. The other disables the instruction-fetch-fault branch ahead of instruction decode and must fail with `EXCEPTION_IRQ_PRIORITY_FAILED`. An arbitrary nonzero exit, compile failure, or timeout is rejected. These are deliberately generated mutations that test the checkers; they are not claims of defects in upstream CV32E40P.

## Run

Requirements are Python 3, Git, a C++ compiler, and Verilator. From any directory:

```sh
/absolute/path/to/riscv-debug-interrupt-verification/setup.sh
```

For an already available clean checkout at the exact revision:

```sh
python3 /absolute/path/to/riscv-debug-interrupt-verification/tools/run.py \
  --source /path/to/cv32e40p
```

The default timeout is 120 seconds per external command. Each invocation preserves compile logs, simulation logs, the generated mutants, source hashes, commands, tool versions, timings, assumptions, and `summary.json` in a unique `runs/` directory. `runs/LATEST` points to the newest run. CI uploads that directory even on failure.

Runner verdict regressions are stdlib-only: `python3 tools/test_runner.py`.

## Scope and assumptions

This is controller-level simulation under default feature parameters (`COREV_PULP=0`, `COREV_CLUSTER=0`, `FPU=0`). The environment uses one clock for gated and ungated inputs, models the instruction pipeline as valid and ready, holds the DRET decode indication through its modeled flush stages, and treats `irq_req_ctrl_i` as the already-qualified request produced by the separate interrupt/CSR logic. Holding that signal models pending state outside this controller; this test does not verify a pending latch or CSR interrupt masks. Likewise, `is_fetch_failed_i` models an instruction access fault already detected outside the controller. The test checks how the controller orders and routes that indication; it does not verify the detector, trap CSR storage, or a complete exception return.

The evidence covers only the transitions and outputs named above. It is not a whole-core software test, formal proof, security assessment, timing result, or claim of RISC-V Debug or privileged-architecture compliance. It does not exercise JTAG/DMI, abstract commands, triggers, nested traps, exception return, trap CSR contents, privilege qualification, clock gating, or every debug and exception cause.

## Upstream license

CV32E40P is fetched from the public upstream repository and remains under its Solderpad Hardware License 0.51, with the upstream option to use Apache License 2.0. See [THIRD_PARTY.md](THIRD_PARTY.md). The original material in this evidence harness is Apache-2.0 licensed.

## Recorded reproduction

[Independent run and raw evidence](recorded/2026-09-15/README.md) preserve the earlier debug/interrupt reproduction. New exception evidence is written separately by the current runner and can be recorded after independent review.
