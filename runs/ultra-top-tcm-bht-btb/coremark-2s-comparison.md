# Ultra `top_tcm_axi` CoreMark 2-second comparison

Date: 2026-09-06

This is an internal performance comparison, not an official CoreMark result.
Each row uses the same `top_tcm_axi` RTL, 100 MHz clock, 64 KiB dual-port TCM,
Verilator/SystemC testbench, `TOTAL_DATA_SIZE=2000`, `MEM_STATIC`,
`MULTITHREAD=1`, and performance seeds `seed1=0`, `seed2=0`, `seed3=0x66`.
The measured interval is the actual `start_time()`/`stop_time()` region around
`iterate()`; initialization, calibration, counter reporting, CRC, signature
dump, and printf are outside it.

The common compiler options are:

```text
-march=rv32im_zicsr -mabi=ilp32 -mcmodel=medany -msmall-data-limit=0
-ffreestanding -fno-builtin -fno-stack-protector -fno-pic
-fdata-sections -ffunction-sections -std=gnu11 -Wall -Wextra
```

Only compiler family/version, `-O2`/`-O3`, and the iteration count vary.

| Compiler | Opt | `.text` bytes | Iterations | Time (s) | Cycles | Retired | Instr/iter | Cycles/iter | CPI | CoreMark/MHz | CRC |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `riscv64-unknown-elf-gcc 13.2.0` | O2 | 11,392 | 476 | 2.004582 | 200,458,240 | 149,148,172 | 313,336.496 | 421,130.756 | 1.344021 | 2.374559 | PASS; final `b40f` |
| `riscv64-unknown-elf-gcc 13.2.0` | O3 | 17,848 | 512 | 2.004342 | 200,434,230 | 153,531,227 | 299,865.678 | 391,473.105 | 1.305495 | 2.554454 | PASS; final `dfc8` |
| `riscv-none-elf-gcc 15.2.0` (xPack) | O2 | 12,992 | 510 | 2.002203 | 200,220,268 | 146,984,754 | 288,205.400 | 392,588.761 | 1.362184 | 2.547195 | PASS; final `3978` |
| `riscv-none-elf-gcc 15.2.0` (xPack) | O3 | 18,540 | 516 | 2.000455 | 200,045,542 | 150,778,530 | 292,206.453 | 387,685.159 | 1.326751 | 2.579413 | PASS; final `e6dc` |

Raw counter boundaries:

| Compiler/opt | `cycle_start` → `cycle_end` | `instret_start` → `instret_end` |
| --- | ---: | ---: |
| GCC 13.2 O2 | 19,069 → 200,477,309 | 14,300 → 149,162,472 |
| GCC 13.2 O3 | 15,823 → 200,450,053 | 12,167 → 153,543,394 |
| xPack 15.2 O2 | 18,764 → 200,239,032 | 13,811 → 146,998,565 |
| xPack 15.2 O3 | 15,791 → 200,061,333 | 11,911 → 150,790,441 |

The fixed component CRCs are `seedcrc=e9f5`, `crclist=e714`,
`crcmatrix=1fd7`, and `crcstate=8e3a` for every row. CoreMark prints
`Errors detected` only because these are intentionally shorter than the normal
10-second validity interval; the component validation itself passes. The
`crcfinal` value changes with the chosen iteration count.

The table is the compiler sweep before the expanded stall observer was added.
The later observer adds 432 bytes of diagnostic code to the xPack O3 `.text`
image, but all of those reads and reports are outside the timed `iterate()`
interval. Its timed cycles, score, and CRC are unchanged; see
`coremark-stall-breakdown.md` for the current observer image size and event
counts.

## Interpretation

The GCC 13.2 O2 baseline is 421,130.756 cycles/iteration and 2.374559
CoreMark/MHz, matching the earlier one-second 2.374568 result. GCC 13.2 O3
reduces instructions/iteration by 4.30% and cycles/iteration by 7.04%. xPack
O3 is the best tested row, reducing instructions/iteration by 6.74% and
cycles/iteration by 7.94% versus the baseline, but reaching only 2.579413
CoreMark/MHz.

At 100 MHz, 2.94 CoreMark/MHz corresponds to about 340,136 cycles/iteration.
The best tested row is still 13.98% more cycles/iteration (12.27% lower score).
If its instruction count stayed fixed, reaching 2.94 would require CPI to fall
from 1.326751 to about 1.164026. Thus compiler/code generation is a real
secondary factor, but the remaining gap is dominated by CPI/pipeline waiting,
not by dynamic instruction count alone.

The disassemblies support the compiler effect: O2 retains separate small helper
symbols such as `core_list_mergesort` and matrix helpers, while O3 inlines them
into larger benchmark functions. This increases static `.text` size; GCC 13.2
O3 lowers dynamic instructions/iteration, while xPack O3 trades a 1.39% higher
instruction count than xPack O2 for a 2.60% lower CPI. The xPack O3
stall/flush breakdown is recorded in `coremark-stall-breakdown.md`: about
23,970 scoreboard-dependency cycles/iteration and 71,509 branch-flush
cycles/iteration account for nearly all of the CPI-1 excess, while LSU, raw
pipe, and DIV waits are zero. No cache, predictor, forwarding, LSU, or
decode-stage change was made here.
