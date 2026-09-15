# CV32E40P temporal debug, interrupt, and exception evidence

This repository runs directed module-level simulations against the real OpenHW Group CV32E40P controller at immutable upstream commit `6033d2b1be3295ec774d17ac4cf226faacfdeb08`. The upstream checkout is verified clean and is never edited in place.

## Executed scenarios

The SystemVerilog bench drives the controller's real FSM and sticky debug-request register through four timing interactions plus a single-step sanity check:

1. `DECODE` is held without a valid instruction. A one-cycle external halt request is removed, then a qualified interrupt arrives while the pipeline remains stalled. When valid/ready return, the retained halt request must enter `DBG_FLUSH` and `DBG_TAKEN_ID` before the interrupt, save `DBG_CAUSE_HALTREQ`, and reach halted debug mode without an interrupt acknowledge.
2. A fetch-fault indication and qualified interrupt arrive together while `instr_valid_i=0` and `id_ready_i=0`. The fetch fault must save the instruction-fault cause and enter `FLUSH_WB` even though decode is invalid; the redirect must select the exception path and the interrupt acknowledge must remain low.
3. During that fetch-fault `FLUSH_WB`, a one-cycle halt request is sampled. It must not disturb the active exception redirect. Once instruction validity returns, the retained request must enter debug before the still-held interrupt.
4. In debug mode, DRET is held in `DECODE` for three cycles with `id_ready_i=0`. No early restore or interrupt acknowledge is allowed. After `FLUSH_EX` and `FLUSH_WB`, the restore strobe must appear. A fresh one-cycle halt request sampled in `XRET_JUMP`, while `debug_mode_q` is still set and DRET clears it, must be retained and re-enter debug before the held interrupt.

The bench also checks the independent single-step cause path. These are deterministic boundary sequences, not random stimulus or whole-core instruction execution.

An ordinary smoke suite preserves the exact three-scenario bench from repository revision `cb2f64c` (SHA-256 `b95bd6a177e49d272cbc6b4204a9e955e8e313f4400a6281b8438caf4c896479`). It covers simultaneous halt/interrupt priority with an uncomplicated DRET and subsequent held-interrupt service, single-step entry, and a fetch fault concurrent with an interrupt. The runner requires the pinned controller and every synthetic mutant to pass this suite. This measures that each defect escapes the earlier happy paths before the temporal bench detects its boundary failure.

A case-selected boundary matrix then records ten exact timing positions. The pinned controller must pass halt pulses with decode stalls of 0, 1, and 3 cycles; a valid-instruction fetch-fault control; halt pulses in `DECODE` before fetch-fault `FLUSH_WB`, during `FLUSH_WB`, and in `DECODE` after it; and halt pulses in DRET `FLUSH_WB` before `XRET_JUMP`, during `XRET_JUMP`, and in `DECODE` after it. Every passing simulation emits its observed pulse position, one-cycle pulse width, stall length, sampled-request result, and eventual service order. The checks retain external interrupt acknowledge, cause-save, exception redirect, DRET restore, and debug-mode assertions alongside internal state localization.

The pre-XRET case has a deliberately different supported outcome: upstream samples the pulse while still in debug mode, then clears the sticky bit as it exits debug, so the held interrupt is serviced after DRET. The mutant's failed pre-XRET sampling check does not independently change that external outcome. The during- and after-XRET pulses persist and re-enter debug before the interrupt; losing the during-XRET pulse changes externally visible priority. The DRET synthetic mutant fails both pre-XRET sampling and during-XRET retention, while the after-XRET case passes. This is recorded as two trigger positions plus an adjacent non-trigger position.

## Synthetic seeded defects

The runner creates four controller copies inside each evidence directory. Each copy changes one condition while leaving the upstream checkout untouched:

- qualify the sticky halt-request latch with `instr_valid_i`, losing a pulse during invalid decode;
- qualify the fetch-fault branch with `instr_valid_i`, incorrectly coupling fetch fault handling to decode validity;
- reject a halt pulse only while the controller is in `FLUSH_WB`, losing the exception-flush request;
- reject a halt pulse while `debug_mode_q` is set, losing the request sampled at the DRET boundary.

These defects preserve ordinary ready/valid halt entry, normal valid-instruction fetch-fault entry, and uncomplicated DRET behavior, as verified by the smoke matrix rather than assumed from inspection. They are explicitly synthetic checker controls and are not claims of upstream CV32E40P bugs. The runner accepts a negative control only when both benches compile, the smoke simulation passes, the temporal simulation fails, and exactly one scenario-specific marker plus exactly one `TEST_FAIL` appear. Compile failures, smoke failures, timeouts, unknown variants, arbitrary crashes, unrelated or duplicated diagnostics, duplicated pass markers, and wrong-marker failures are rejected.

## Run

Requirements are Python 3, Git, a C++ compiler, and Verilator. From any directory:

```sh
/absolute/path/to/riscv-debug-interrupt-verification/setup.sh
```

For an existing clean checkout at the exact pinned revision:

```sh
python3 /absolute/path/to/riscv-debug-interrupt-verification/tools/run.py \
  --source /path/to/cv32e40p
```

To create a reviewable recorded run at a new path:

```sh
python3 tools/run.py --source third_party/cv32e40p \
  --evidence-dir recorded/2026-09-15-temporal-v3
```

The default timeout is 120 seconds per external command. Every run records compile and simulation logs, exact commands, return codes, timeouts, measured durations, tool and platform versions, source hashes, assumptions, generated mutant RTL, and `summary.json`. Normal runs use unique directories under `runs/`; `runs/LATEST` names the newest normal run. The explicit evidence directory must not already exist.

Runner-verdict regressions use only the Python standard library:

```sh
python3 tools/test_runner.py
```

## Scope and limits

This is controller-level RTL simulation under default feature parameters (`COREV_PULP=0`, `COREV_CLUSTER=0`, `FPU=0`). It uses one shared gated/ungated clock and drives pipeline validity directly at the module boundary. `irq_req_ctrl_i` is already qualified by interrupt/CSR logic outside this module; holding it models pending state elsewhere. `is_fetch_failed_i` is an already-detected instruction access fault and is held through `FLUSH_WB`, matching this controller interface's redirect dependency.

The evidence covers only the named transitions, outputs, and relative ordering. It is not a whole-core software test, formal proof, clock-domain-crossing analysis, security assessment, performance result, or architecture-compliance claim. It does not cover JTAG/DMI, abstract commands, trigger behavior, nested traps, trap CSR contents, privilege qualification, separate gated-clock behavior, PULP/cluster feature branches, or exhaustive causes and pipeline hazards.

## Provenance

CV32E40P remains under its Solderpad Hardware License 0.51, with the upstream Apache License 2.0 option. See [THIRD_PARTY.md](THIRD_PARTY.md). This harness is Apache-2.0 licensed.

Raw logs and machine-readable results from the final local reproduction are retained under [`recorded/2026-09-15-temporal-v3`](recorded/2026-09-15-temporal-v3/README.md). Earlier recorded directories remain as historical reproductions.
