# Ultra `top_tcm_axi` CoreMark stall/flush breakdown

Date: 2026-09-06

This is an internal, non-official CoreMark comparison. It uses the same
`top_tcm_axi`, 100 MHz clock, 64 KiB dual-port TCM, `TOTAL_DATA_SIZE=2000`,
performance seeds, xPack `riscv-none-elf-gcc 15.2.0`, `-O3`, and 516
iterations. The measured benchmark interval remains only the existing
`start_time()`/`stop_time()` region around `iterate()`; initialization,
calibration, diagnostics, CRC and printing are outside it. The run lasted
about two seconds, so CoreMark correctly reports that it is not a valid
10-second certification run.

## CoreMark result

| Item | Result |
| --- | ---: |
| `.text` bytes | 18,972 |
| Iterations | 516 |
| Cycles | 200,045,542 |
| Retired instructions | 150,778,557 |
| Instructions/iteration | 292,206.506 |
| Cycles/iteration | 387,685.159 |
| CPI | 1.326751 |
| Equivalent CoreMark/MHz | 2.579413 |
| Component CRC | PASS |
| Final CRC | `e6dc` |

## Counter result

| Event | Total | Per iteration | Definition |
| --- | ---: | ---: | --- |
| Scoreboard dependency | 12,368,613 | 23,970.180 | A valid decoded instruction has a scoreboard RAW conflict while LSU/pipe/DIV/CSR backend blocks are inactive. |
| LSU stall | 0 | 0.000 | Existing `lsu_stall_i` from the LSU. |
| Pipe stall | 0 | 0.000 | Existing `pipe_stall_raw_w` / `stall_w` from `riscv_pipe_ctrl`. |
| DIV wait | 0 | 0.000 | Existing `div_pending_q`. |
| CSR wait | 0 | 0.000 | Existing `csr_pending_q`, excluding the timing/HPM diagnostic reads. |
| Branch request | 18,449,206 | 35,754.275 | Taken execute-stage branch requests (`branch_d_exec_request_w`); this is an event count. |
| Branch redirect | 18,449,206 | 35,754.275 | Cycles in which the buffered target PC is actually applied in fetch. |
| Branch flush | 36,898,412 | 71,508.550 | Cycles in which fetch responses are suppressed by the redirect path. |
| Fetch starvation | 0 | 0.000 | `!fetch_valid_o` with no fetch/backend stall and no branch-response drop. |

The event counters are observers only and are available through standard
machine HPM read addresses when `ULTRA_PERF_COUNTERS` is defined:

| CSR | Event |
| --- | --- |
| `mhpmcounter3` (`0xb03`) | scoreboard dependency |
| `mhpmcounter4` (`0xb04`) | LSU stall |
| `mhpmcounter5` (`0xb05`) | pipe stall |
| `mhpmcounter6` (`0xb06`) | DIV wait |
| `mhpmcounter7` (`0xb07`) | CSR wait |
| `mhpmcounter8` (`0xb08`) | branch request |
| `mhpmcounter9` (`0xb09`) | branch redirect |
| `mhpmcounter10` (`0xb0a`) | branch flush |
| `mhpmcounter11` (`0xb0b`) | fetch starvation |

## Interpretation

The ideal CPI-1 excess is:

```text
cycles - retired = 49,266,985 total
                  = 95,478.653 cycles/iteration
```

The two dominant observer counts are:

```text
scoreboard + branch_flush
= 12,368,613 + 36,898,412
= 49,267,025 cycles
```

The 40-cycle difference is a small measurement-boundary/observer accounting
residual. In per-iteration terms the two counters close the CPI excess to
within 0.08 cycle/iteration. There is no measurable TCM/LSU wait, raw pipe
stall, or DIV wait in this run. Branch flush is exactly two counted fetch-drop
cycles per taken branch in this configuration.

At 100 MHz, 2.94 CoreMark/MHz requires about 340,136.054 cycles/iteration.
The current result is 47,549.105 cycles/iteration above that target. Removing
the entire scoreboard component would still leave about 363,715 cycles per
iteration; removing the branch-flush component alone would leave about
316,177 cycles per iteration. Therefore the first architectural performance
candidate is the branch redirect/flush path, followed by load/multiply
scoreboard dependencies. This conclusion does not authorize or include a
BTB, branch predictor, forwarding, LSU, cache, or decode-stage change.

The instrumentation is guarded by `ULTRA_PERF_COUNTERS`; the Vivado FPGA
baseline project does not define that macro.
