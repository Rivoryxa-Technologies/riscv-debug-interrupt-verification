# Independent reproduction, 15 September 2026

A fresh local clone of harness revision `7899131` fetched the unchanged OpenHW CV32E40P source at `6033d2b1be3295ec774d17ac4cf226faacfdeb08` and ran `setup.sh`. The correct controller passed both directed scenarios. A separate generated priority mutant failed with the required debug/interrupt diagnostic. Two runner regressions passed.

[summary.json](summary.json) records the exact source hashes, tools, commands, compile and simulation durations, and results. The raw logs retain the unconnected-output and other compiler warnings for inspection. Generated C++ and executables are omitted; the runner builds them on each invocation.

Read the assumptions in the root README. These are controller-level checks with modelled pipeline inputs and an already-qualified interrupt request. They do not verify the separate CSR masking or pending interrupt logic, full instruction execution, or the RISC-V Debug Specification. Measured runtimes are not project delivery estimates.

The generated mutant retains the upstream copyright/license header; upstream licensing is described in `THIRD_PARTY.md` at the repository root.
