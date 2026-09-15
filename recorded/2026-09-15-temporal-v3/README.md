# Controller boundary matrix reproduction, 15 September 2026

This run used harness commit `996cb0d14d4fabdf41461ab1b5325b403612c262` and the clean pinned CV32E40P source at `6033d2b1be3295ec774d17ac4cf226faacfdeb08`.

```sh
python3 tools/test_runner.py
python3 tools/run.py --source third_party/cv32e40p \
  --evidence-dir recorded/2026-09-15-temporal-v3
```

All 11 fail-closed runner regressions passed. The correct controller and all four synthetic mutants also retained the v2 results: every variant passed the exact prior ordinary smoke bench; correct RTL passed the combined temporal bench; and each mutant failed that temporal bench with exactly its own diagnostic.

The new case-selected matrix produced these results. A pass log contains one machine-checked `BOUNDARY_EXERCISE` record whose values match the case metadata. A target failure contains exactly the named failure marker and no completed exercise record.

| RTL | Scenario | Pulse position / stall | Expected and observed result |
| --- | --- | --- | --- |
| correct | `STALL_0` | valid `DECODE`, 0 cycles | halt sampled and serviced before IRQ |
| correct | `STALL_1` | invalid `DECODE`, 1 cycle | halt sampled and serviced before IRQ |
| correct | `STALL_3` | invalid `DECODE`, 3 cycles | halt sampled and serviced before IRQ |
| correct | `FETCH_VALID` | no halt, valid fetch fault | exception redirect before IRQ |
| correct | `FLUSH_BEFORE` | faulting `DECODE`, before `FLUSH_WB` | halt sampled and serviced before IRQ |
| correct | `FLUSH_DURING` | fetch-fault `FLUSH_WB` | halt sampled and serviced before IRQ |
| correct | `FLUSH_AFTER` | recovered `DECODE`, after `FLUSH_WB` | halt sampled and serviced before IRQ |
| correct | `XRET_BEFORE` | DRET `FLUSH_WB`, before `XRET_JUMP` | sampled, then cleared by supported debug exit; IRQ after DRET |
| correct | `XRET_DURING` | DRET `XRET_JUMP` | halt sampled and serviced before IRQ |
| correct | `XRET_AFTER` | resumed `DECODE`, after `XRET_JUMP` | halt sampled and serviced before IRQ |
| stalled-pulse mutant | `STALL_0` / `STALL_3` | adjacent valid / target 3-cycle invalid | adjacent pass / exact target failure |
| fetch-valid mutant | `FETCH_VALID` / `FLUSH_BEFORE` | adjacent valid / target invalid | adjacent pass / exact target failure |
| exception-flush mutant | before / during / after `FLUSH_WB` | adjacent / target / adjacent | pass / exact target failure / pass |
| DRET-rehalt mutant | before / during / after `XRET_JUMP` | trigger / trigger / adjacent | exact sampling failure / exact lost-halt failure / pass |

All request pulses are one clock cycle. Passing cases assert the observed FSM position and external interrupt acknowledge, cause-save, redirect, restore, and debug-mode signals relevant to that phase. The pre-XRET mutant failure is an internal sampling difference with the same eventual upstream external outcome; the during-XRET failure is the externally meaningful loss of halt priority.

The main compile/simulation times in seconds were: correct `3.511021/0.157980`; stalled-pulse mutant `3.472253/0.179221`; fetch-valid mutant `3.459804/0.183635`; exception-flush mutant `3.440449/0.454170`; and DRET-rehalt mutant `3.411552/0.509120`. Ordinary-smoke compile/simulation times were respectively `3.417761/0.266813`, `3.494949/0.174399`, `3.381269/0.258447`, `3.430675/0.507526`, and `3.436379/0.527406`. Boundary builds took 3.75–3.88 seconds per variant; individual case timings and exact commands are in `summary.json`.

Environment: macOS 26.6.2 arm64, Python 3.9.6, Verilator 5.050 (2026-07-01). [`summary.json`](summary.json) separates expected metadata from parsed observed exercise data and records hashes for the source, benches, runner, generated mutant RTL, and every compile/simulation/case log. Generated build directories were removed; all retained evidence is reproducible from the commands above. Scope and interface assumptions remain those in the root README.
