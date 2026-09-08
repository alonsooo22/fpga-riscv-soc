# Historical CoreMark 1-second smoke baseline

Date: 2026-09-06

This is a short, equivalent CoreMark baseline for the isolated Ultra scalar
`top_tcm_axi` run. It is not an official CoreMark result because the benchmark
was intentionally run for about one second instead of the required ten-second
reporting interval.

## Configuration

- RTL target: Ultra `top_tcm_axi`
- Clock: `CLK0_PERIOD=10 ns` = 100 MHz
- CoreMark iterations: 238
- CoreMark data size: 2000 bytes, static memory
- ISA: `rv32im_zicsr`, ABI: `ilp32`
- Compiler: `riscv64-unknown-elf-gcc 13.2.0` inside the isolated container
- Verilator: 5.050
- SystemC: 2.3.1a
- Memory location: 64 KiB TCM
- Waves: disabled

## Measured result

- Total ticks: 100,228,773
- Measured time: 1.002288 s
- Equivalent CoreMark/s: **237.457**
- Equivalent CoreMark/MHz: **2.374568**

The conversion uses the measured RTL counter rather than the nominal iteration
calibration:

```text
CoreMark/s  = iterations * 100,000,000 / total_ticks
CoreMark/MHz = CoreMark/s / 100
```

## Functional signature

- `seedcrc`: `0xe9f5`
- `crclist`: `0xe714`
- `crcmatrix`: `0x1fd7`
- `crcstate`: `0x8e3a`
- `crcfinal`: `0x07b6`

The component CRCs match the expected CoreMark values. The simulator output
contains `Errors detected` only because the ten-second validity rule was
intentionally not enabled for this smoke baseline.

Signature dump: `top_tcm_axi/tb/coremark.signature.bin`
