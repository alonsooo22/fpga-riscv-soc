# Ultra scalar `top_tcm_axi` parameter sweep

## Scope and method

This is a four-way comparison of the two existing Ultra configuration
parameters only. The CPU microarchitecture, TCM, software image, compiler and
benchmark seeds are held constant:

| Item | Value |
|---|---|
| Device | `xc7z020clg400-1` |
| Top | `riscv_tcm_top` from `top_tcm_axi` |
| Memory | 64 KiB dual-port TCM, 16 `RAMB36E1` |
| Clock constraint | 10.000 ns (100 MHz) |
| CPU options | MULDIV=1, load/mul bypass=1, SUPER=0, MMU=0 |
| CoreMark | `TOTAL_DATA_SIZE=2000`, standard performance seeds |
| Software | xPack GCC 15.2.0, `-O3`, RV32IM/Zicsr, ILP32 |
| Simulation | Verilator 5.050/SystemC, approximately 2 seconds of timed work |
| FPGA flow | Vivado 2022.2 OOC synth, opt, place, phys_opt, route |

The top-level RTL only exposes the already-existing Ultra parameters so
Verilator and Vivado can select them reproducibly. No cache, predictor, LSU,
forwarding or other microarchitectural change was made.

The CoreMark timer starts after initialization and stops before diagnostic
printing. The cycle and retired-instruction boundaries are read from the
performance counter snapshots. The 2-second run is intentionally not an
official 10-second CoreMark submission; the CoreMark validity warning is
expected, while the CRC fields pass in every configuration.

## CoreMark results

| Config | Decode stage | Xilinx RF | `.text` | Iterations | Cycles | Retired instructions | Instructions/iteration | Cycles/iteration | CPI | CoreMark/MHz | CRC |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| A | 0 | 0 | 18,972 | 516 | 200,045,542 | 150,778,557 | 292,206.506 | 387,685.159 | 1.326751 | 2.579413 | PASS |
| B | 1 | 0 | 18,972 | 516 | 218,494,748 | 150,778,556 | 292,206.504 | 423,439.434 | 1.449110 | 2.361613 | PASS |
| C | 0 | 1 | 18,972 | 516 | 200,045,542 | 150,778,557 | 292,206.506 | 387,685.159 | 1.326751 | 2.579413 | PASS |
| D | 1 | 1 | 18,972 | 516 | 218,494,748 | 150,778,556 | 292,206.504 | 423,439.434 | 1.449110 | 2.361613 | PASS |

The per-iteration observer values are unchanged across configurations:

- scoreboard dependency: `23,970.180 cycles/iteration`
- branch redirect: `35,754.275 cycles/iteration`
- branch flush: `71,508.550 cycles/iteration`
- LSU, pipe, DIV, CSR and fetch-starvation counters: zero

B/D add `35,754.275 cycles/iteration`, exactly one branch-redirect-count
equivalent per iteration, while retired instructions remain unchanged. Thus
the decode-stage cost is a CPI/control-flow bubble, not a dynamic-instruction
count increase.

## Routed FPGA results

Fmax is estimated from the post-route WNS using
`Fmax = 1000 / (10.000 - WNS)` MHz. All four runs completed route with zero
unrouted nets, zero unconstrained internal endpoints and zero Vivado errors.

| Config | WNS (ns) | TNS (ns) | Fmax (MHz) | LUT | FF | BRAM36 | DSP |
|---|---:|---:|---:|---:|---:|---:|---:|
| A | -3.080 | -1,563.026 | 76.453 | 3,640 | 2,666 | 16 | 4 |
| B | -2.132 | -674.603 | 82.427 | 3,646 | 2,736 | 16 | 4 |
| C | -3.599 | -1,838.485 | 73.535 | 3,338 | 1,674 | 16 | 4 |
| D | -1.887 | -614.715 | 84.126 | 3,366 | 1,755 | 16 | 4 |

## Combined comparison

`CoreMark/s = CoreMark/MHz × routed Fmax(MHz)` and
`CoreMark/s/LUT = CoreMark/s / LUT`.

| Config | Decode stage | Xilinx RF | CM/MHz | CPI | Fmax | CoreMark/s | LUT | CM/s/LUT | Critical path |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| A | 0 | 0 | 2.579413 | 1.326751 | 76.453 | 197.203 | 3,640 | 0.054177 | TCM BRAM `CLKBWRCLK` → `u_fetch/branch_pc_q_reg[29]/D` |
| B | 1 | 0 | 2.361613 | 1.449110 | 82.427 | 194.660 | 3,646 | 0.053390 | TCM BRAM `CLKARDCLK` → `u_fetch/branch_pc_q_reg[21]/CE` via LSU/result cone |
| C | 0 | 1 | 2.579413 | 1.326751 | 73.535 | 189.677 | 3,338 | 0.056823 | TCM BRAM `CLKBWRCLK` → `u_lsu/mem_data_wr_q_reg[30]/D` |
| D | 1 | 1 | 2.361613 | 1.449110 | 84.126 | 198.672 | 3,366 | 0.059023 | `u_decode/buffer_q_reg[45]/C` → `u_lsu/mem_data_wr_q_reg[19]/D` |

## Critical-path interpretation

- A's worst path is the expected instruction-BRAM output through fetch/decode,
  register-file select, issue/execute control and branch-PC update. Its data
  delay is `12.982 ns`, with `4.805 ns` logic and `8.177 ns` routing.
- B removes the original straight-through decode boundary from the worst
  path. Its worst path is `11.817 ns` and still begins at TCM BRAM, but now
  ends at the branch-PC clock-enable cone after LSU/result logic.
- C does not shorten a regfile/issue critical path. The worst path is a
  BRAM-to-LSU store-data path, `13.543 ns`, with routing still dominant.
- D's worst path no longer starts at BRAM; it is a decode-buffer-to-LSU
  store-data path of `11.797 ns`. The remaining delay is predominantly
  routing (`74.554%`), not a Xilinx-RF read path.

Hierarchical utilization explains the area result. The ordinary register file
in A/B uses `512/517` logic LUTs and `992` FFs. The Xilinx implementation in
C/D uses `256` LUTRAMs (plus `0/5` logic LUTs) and `0` FFs for the regfile.
Therefore Xilinx RF lowers total LUT/FF counts substantially, but this
experiment does not show a direct regfile/issue timing win; the critical path
moves through other cones.

## Answers and baseline choice

1. `EXTRA_DECODE_STAGE=1` raises routed Fmax from `76.453` to `82.427 MHz`
   with the ordinary RF (`+7.8%`), and from `73.535` to `84.126 MHz` with
   Xilinx RF (`+14.4%`). Its cost is `2.579413 → 2.361613 CM/MHz`
   (`-8.44%`) and `1.326751 → 1.449110 CPI`; the extra cycles are control-flow
   bubbles, not extra instructions. At the final routed Fmax, A→B slightly
   reduces CoreMark/s, while C→D increases it because C's RF placement is
   particularly unfavorable.
2. `SUPPORT_REGFILE_XILINX=1` lowers A→C area by `302 LUT` and `992 FF`, and
   B→D by `280 LUT` and `981 FF`. It does not shorten the regfile/issue
   critical path in this run: A→C actually loses Fmax (`-3.82%`), while the
   B→D improvement is a small `+2.06%` placement/interaction result and has a
   decode/LSU critical path, not a regfile path.
3. D is the best holistic FPGA baseline: it has the highest routed Fmax,
   highest estimated CoreMark/s (`198.672`) and highest performance density
   (`0.059023 CM/s/LUT`), while retaining the much smaller Xilinx-RF area.
   A should remain as the per-cycle/CM-MHz control reference. No BTB/BHT or
   other next-stage microarchitectural optimization was added in this round.

## Artifacts

- CoreMark logs and isolated generated models: `runs/ultra-top-tcm/experiments/param_sweep/coremark/{A,B,C,D}`
- Combined CoreMark CSV: `runs/ultra-top-tcm/experiments/param_sweep/coremark/coremark_metrics_all.csv`
- Routed Vivado reports: `vivado/ultra_scalar_top_tcm_xc7z020/reports/param_sweep/{A,B,C,D}`
