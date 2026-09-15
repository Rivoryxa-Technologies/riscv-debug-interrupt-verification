# Temporal and ordinary-smoke reproduction, 15 September 2026

This recorded run was produced from harness commit `1642bf63c208fb5a3ec1be02fdbaf8569e72033f` with the pinned, clean CV32E40P source at `6033d2b1be3295ec774d17ac4cf226faacfdeb08`.

Commands executed from the repository root:

```sh
python3 tools/test_runner.py
python3 tools/run.py --source third_party/cv32e40p \
  --evidence-dir recorded/2026-09-15-temporal-v2
```

All seven verdict-classification regressions passed. Each row below contains two independent compile/simulation pairs: the temporal boundary bench and the exact prior three-scenario smoke bench from `cb2f64c`. Every variant passed the smoke suite. The pinned controller passed the temporal suite, while each synthetic defect failed fast with exactly its own expected diagnostic.

| Variant | Temporal compile / simulation | Ordinary smoke compile / simulation |
| --- | --- | --- |
| pinned upstream controller | 3.605836 s / 0.163917 s, exit 0, pass | 3.802183 s / 0.170581 s, exit 0, pass |
| synthetic stalled-debug-pulse mutant | 3.727513 s / 0.461097 s, exit 1, `PULSED_DEBUG_RETENTION_FAILED` | 3.715614 s / 0.452655 s, exit 0, pass |
| synthetic fetch-valid-coupling mutant | 3.715207 s / 0.445495 s, exit 1, `STALLED_FETCH_FAULT_PRIORITY_FAILED` | 3.698113 s / 0.462099 s, exit 0, pass |
| synthetic exception-flush-debug mutant | 4.120278 s / 0.459063 s, exit 1, `EXCEPTION_FLUSH_DEBUG_FAILED` | 4.104858 s / 0.457570 s, exit 0, pass |
| synthetic DRET-rehalt mutant | 4.024915 s / 0.460126 s, exit 1, `DRET_REHALT_PRIORITY_FAILED` | 3.795861 s / 0.488863 s, exit 0, pass |

Environment: macOS 26.6.2 arm64, Python 3.9.6, and Verilator 5.050 (2026-07-01). The machine-readable [`summary.json`](summary.json) contains exact argv arrays, return codes, timeout flags, source hashes, per-log hashes, generated-mutant hashes, assumptions, and measured durations. Raw logs and the generated one-condition mutant sources are retained beside it. The mutants are checker controls, not alleged upstream defects. Reproducible Verilator build products were removed from this recorded directory.

The ordinary suite empirically preserves normal simultaneous debug/interrupt behavior, single-step, valid-instruction fetch-fault priority, and DRET followed by service of a held pending interrupt. The temporal suite adds stalled decode, invalid fetch, exception-flush debug arrival, and DRET re-halt boundaries. Scope remains controller-level simulation as detailed in the root README; timings describe this local run only.
