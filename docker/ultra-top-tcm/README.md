# Ultra `top_tcm_axi` isolated Docker environment

This environment is dedicated to the Ultra scalar baseline. It uses the official
`verilator/verilator:v5.050` image and adds:

- GNU Make and host C/C++ build tools;
- SystemC `2.3.1a`, installed as `/usr/local/systemc-2.3.1`;
- `libelf-dev` and `binutils-dev` for Ultra `isa_sim`;
- an unmodified Ubuntu `riscv64-unknown-elf` cross toolchain for RV32 builds.

The source archive used to build SystemC is kept in this directory so the image
build does not depend on another project or another workspace.

## Isolation boundary

`run.ps1` creates a separate working copy at:

`D:\code\FPGA\runs\ultra-top-tcm`

The container mounts only that working copy at `/workspace/ultra-riscv`. It does
not mount `D:\code`, other repositories, the Vexii workspace, or the original
baseline. Build products and traces therefore stay in the Ultra run directory.

## Commands

From this directory:

```powershell
.\run.ps1 build-image
.\run.ps1 build
.\run.ps1 run
.\run.ps1 coremark-build
.\run.ps1 coremark-quick
.\run.ps1 coremark-smoke
.\run.ps1 coremark-sweep
.\run.ps1 coremark-xpack-sweep
.\run.ps1 coremark-full
.\run.ps1 shell
.\run.ps1 clean
```

The `build` and `run` actions execute the upstream `top_tcm_axi/tb/makefile`.
The default test image is `../../isa_sim/images/basic.elf`.

`coremark-build` builds a 16-iteration ELF, `coremark-quick` builds and runs a
single-iteration RTL smoke test, `coremark-smoke` runs a short performance
comparison, and `coremark-full` builds/runs the standard 18000-iteration
target. The smoke action parses the measured RTL cycle and retired-instruction
counters and prints equivalent CoreMark/s, CoreMark/MHz, instructions/iteration,
cycles/iteration, and CPI. Its default 476 iterations is calibrated to about
two seconds for GCC 13.2 `-O2` at the 100 MHz, 10 ns `top_tcm_axi` clock.
`coremark-sweep` automatically uses 476 iterations for GCC 13.2 `-O2` and 512
for `-O3`; `coremark-xpack-sweep` uses 510 and 516 for xPack GCC 15.2. Override
the base count with `-SmokeIterations` when the core configuration changes.
Override the assumed clock with `-CoremarkFrequencyHz`.

The smoke result is deliberately not an official CoreMark score because it is
shorter than the required 10-second reporting interval. It is intended as a
repeatable functional/performance baseline for this exact RTL, compiler, TCM
layout, and simulator configuration. The signature is written to
`runs\ultra-top-tcm\top_tcm_axi\tb\coremark.signature.bin`.

The historical one-second result is recorded in
`runs\ultra-top-tcm\coremark-smoke-baseline.md`. The current compiler sweep,
including cycle/instret boundaries and assembly observations, is recorded in
`runs\ultra-top-tcm\coremark-2s-comparison.md`.

The xPack `-O3` stall/flush observer run is recorded in
`runs\ultra-top-tcm\coremark-stall-breakdown.md`. Its counters are read
through `mhpmcounter3..11` only when `ULTRA_PERF_COUNTERS` is defined; they do
not alter the normal scalar CPU configuration.

The current CoreMark port is TCM-only and does not require the full Ultra SoC:
`top_tcm_axi` supplies the 64 KiB TCM and the Ultra ISA simulator loads the
ELF into it. Use the separate `ultraembedded-riscv_soc` baseline later when
external memory or peripherals are needed.

The run-only compatibility overlay keeps the upstream baseline untouched. It
provides Verilator 5/SystemC compatibility, uses optimized Verilated C++
(`-O3`), exposes the RTL's Verilator-public committed PC so `-r _halt` can
terminate a bare-metal image, and conditionally adds a performance-only
`minstret` counter sourced from the writeback/commit valid signal. The counter
overlay does not change the CPU parameters or normal behavior.

The target ISA for software builds is:

```text
-march=rv32im_zicsr -mabi=ilp32 -mcmodel=medany -msmall-data-limit=0
```
