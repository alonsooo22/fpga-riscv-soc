# Project working agreements

- Active development baseline: `v0.1.0-coremark-baseline`; acceptance scope and deferred work are in `BASELINE.md`.
- Primary RTL workspace: `runs/ultra-top-tcm-bht-btb`. Preserve existing layout and interfaces.
- User accepted CoreMark execution as the current version gate. Do not automatically reopen deferred IRQ, side-effect or frontend coverage work unless requested or relevant to a new change.
- Reuse existing results when changes do not affect measured behavior/configuration/software/timing constraints. Do not rebuild or rerun CoreMark/Vivado solely to obtain one identical source snapshot.
- Select checks according to the actual change. Functional RTL changes still need focused verification; expand only when evidence warrants it.
- Main local configuration is D1; retain A1 and predictor-off alternatives. Application/NPU work follows CPU/SoC and advanced design work.
- `references`, other run directories and original baseline directories are outside this repository's tracked scope. Do not modify them incidentally.
- Keep generated caches, waveforms, tool installations and large implementation products out of Git. Keep small necessary evidence and scripts.
- The existing execution task is called 执行代理. This repository does not authorize automatic messages, tasks, or background work.
