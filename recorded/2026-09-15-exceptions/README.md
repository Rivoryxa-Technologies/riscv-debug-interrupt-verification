# Independent exception extension reproduction, 15 September 2026

A fresh local clone of revision `35eb08f` fetched the pinned upstream source and executed `./setup.sh` followed by `python3 tools/test_runner.py`.

The correct controller passed all three directed scenarios. The debug-priority and exception-priority mutants each failed with their required diagnostic. All three runner classification tests passed. Raw logs and the machine-readable summary are retained here; generated build products are excluded.

The added exception scenario checks controller priority, cause-save controls, and exception redirection for an already-detected instruction fetch fault. It does not test the fault detector, CSR storage, exception return, or complete processor execution. Source and license provenance is in the root README and THIRD_PARTY.md. Tool times are not delivery estimates.
