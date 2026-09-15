# Temporal controller reproduction, 15 September 2026

This recorded run was produced from harness commit `0d110209eab6377385000cb5edb4e57876f6f038` with the pinned, clean CV32E40P source at `6033d2b1be3295ec774d17ac4cf226faacfdeb08`.

Commands executed from the repository root:

```sh
python3 tools/test_runner.py
python3 tools/run.py --source third_party/cv32e40p \
  --evidence-dir recorded/2026-09-15-temporal
```

The five runner-classification regressions passed. The RTL matrix produced these expected outcomes:

| Variant | Compile | Simulation | Expected evidence |
| --- | ---: | ---: | --- |
| pinned upstream controller | 3.907606 s | 0.409414 s, exit 0 | full temporal bench passed |
| synthetic stalled-debug-pulse mutant | 3.592893 s | 0.459729 s, exit 1 | `PULSED_DEBUG_RETENTION_FAILED` detected |
| synthetic fetch-valid-coupling mutant | 3.609190 s | 0.522658 s, exit 1 | `STALLED_FETCH_FAULT_PRIORITY_FAILED` detected |
| synthetic exception-flush-debug mutant | 3.912202 s | 0.445239 s, exit 1 | `EXCEPTION_FLUSH_DEBUG_FAILED` detected |
| synthetic DRET-rehalt mutant | 4.381912 s | 0.454440 s, exit 1 | `DRET_REHALT_PRIORITY_FAILED` detected |

Environment: macOS 26.6.2 arm64, Python 3.9.6, and Verilator 5.050 (2026-07-01). The machine-readable [`summary.json`](summary.json) contains exact argv arrays, return codes, timeout flags, source hashes, assumptions, and measured durations. Compile and simulation logs are retained beside it. Generated mutant source files show the exact one-condition synthetic changes; they are checker controls, not alleged upstream defects. Build products were removed after the run because they add no independent evidence and are reproducible from the recorded commands.

The evidence is limited to the controller-level timing interactions described in the root README. Tool durations describe this local run only and are not performance claims.
