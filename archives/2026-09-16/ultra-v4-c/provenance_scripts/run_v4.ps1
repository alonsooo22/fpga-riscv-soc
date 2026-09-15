[CmdletBinding()]
param(
    [ValidateSet('Build', 'FetchRecovery', 'ShortOff', 'ShortOn', 'BoundedDiag', 'FullCoremark')]
    [string]$Action = 'Build'
)

$ErrorActionPreference = 'Stop'
$helper = Join-Path $PSScriptRoot '..\ultra_dev.ps1'

function Invoke-Ultra([string]$Command) {
    & $helper -Action Exec -Command $Command
    if ($LASTEXITCODE -ne 0) { throw "Ultra v4 action failed: $Action" }
}

switch ($Action) {
    'Build' {
        $cmd = @'
set -e
cd /work/early_tcm_e_tcm_v4/isa_sim
make -B lib
cd /work/early_tcm_e_tcm_v4/top_tcm_axi/tb
make -B -f makefile.generate_verilated CORE=riscv OUTPUT_DIR=verilated_v4_off VERILATE_PARAMS="--trace -Wno-fatal -DULTRA_PERF_COUNTERS -DULTRA_SCOREBOARD_TRACE -GSUPPORT_BRANCH_PREDICTION=1 -GEXTRA_DECODE_STAGE=1 -GSUPPORT_REGFILE_XILINX=1 -GSUPPORT_EARLY_TCM_LOAD=0" VERILATOR_OPTS="--pins-sc-uint --l2-name v --Wno-fatal"
make -B -f makefile.build_verilated SRC_DIR=verilated_v4_off OBJ_DIR=obj_v4_off/ LIB_DIR=lib_v4_off/
make -B -f makefile.build_sysc_tb VERILATED_DIR=./verilated_v4_off OBJ_DIR=obj_v4_tb_off/ EXE_DIR=build_v4_off/ TARGET=test_v4_off.x LIB_PATH="/work/early_tcm_e_tcm_v4/top_tcm_axi/tb/lib_v4_off /work/early_tcm_e_tcm_v4/isa_sim"
make -B -f makefile.generate_verilated CORE=riscv OUTPUT_DIR=verilated_v4_on VERILATE_PARAMS="--trace -Wno-fatal -DULTRA_PERF_COUNTERS -DULTRA_SCOREBOARD_TRACE -GSUPPORT_BRANCH_PREDICTION=1 -GEXTRA_DECODE_STAGE=1 -GSUPPORT_REGFILE_XILINX=1 -GSUPPORT_EARLY_TCM_LOAD=1" VERILATOR_OPTS="--pins-sc-uint --l2-name v --Wno-fatal"
make -B -f makefile.build_verilated SRC_DIR=verilated_v4_on OBJ_DIR=obj_v4_on/ LIB_DIR=lib_v4_on/
make -B -f makefile.build_sysc_tb VERILATED_DIR=./verilated_v4_on OBJ_DIR=obj_v4_tb_on/ EXE_DIR=build_v4_on/ TARGET=test_v4_on.x LIB_PATH="/work/early_tcm_e_tcm_v4/top_tcm_axi/tb/lib_v4_on /work/early_tcm_e_tcm_v4/isa_sim"
test -x build_v4_off/test_v4_off.x
test -x build_v4_on/test_v4_on.x
test -f lib_v4_off/libsyscverilated.a
test -f lib_v4_on/libsyscverilated.a
'@
        Invoke-Ultra $cmd
    }
    'FetchRecovery' {
        $cmd = @'
set -e
cd /work/early_tcm_e_tcm_v4/short
rm -rf fetch_recovery_obj_v4
verilator --binary --timing -Wno-fatal --Mdir fetch_recovery_obj_v4 \
    --top-module fetch_recovery_tb -I/work/early_tcm_e_tcm_v4/core/riscv \
    /work/early_tcm_e_tcm_v4/core/riscv/riscv_fetch.v fetch_recovery_tb.sv
test -x fetch_recovery_obj_v4/Vfetch_recovery_tb
rm -f /followup/reports/early_tcm_e_tcm_v4/fetch_recovery.log
set +e
./fetch_recovery_obj_v4/Vfetch_recovery_tb > /followup/reports/early_tcm_e_tcm_v4/fetch_recovery.log 2>&1
rc=$?
set -e
cat /followup/reports/early_tcm_e_tcm_v4/fetch_recovery.log
test "$rc" -eq 0
grep -q 'FETCH_RECOVERY_PASS' /followup/reports/early_tcm_e_tcm_v4/fetch_recovery.log
'@
        Invoke-Ultra $cmd
    }
    'ShortOff' {
        $cmd = @'
set -e
cd /work/early_tcm_e_tcm_v4/top_tcm_axi/tb
test -f ./lib_v4_off/libsyscverilated.a
env ENABLE_WAVES=no ./build_v4_off/test_v4_off.x \
    -f /work/early_tcm_e_tcm_v4/short/build/etcm_probe.elf -r 0x2210 -c 2000 \
    > /followup/reports/early_tcm_e_tcm_v4/short_off_v4.log 2>&1
cat /followup/reports/early_tcm_e_tcm_v4/short_off_v4.log
grep -q 'branch_resolved       : 4' /followup/reports/early_tcm_e_tcm_v4/short_off_v4.log
grep -q 'branch_mispredict     : 3' /followup/reports/early_tcm_e_tcm_v4/short_off_v4.log
! grep -q 'FAIL' /followup/reports/early_tcm_e_tcm_v4/short_off_v4.log
test ! -e verilator.vcd
test ! -e sysc_wave.vcd
'@
        Invoke-Ultra $cmd
    }
    'ShortOn' {
        $cmd = @'
set -e
cd /work/early_tcm_e_tcm_v4/top_tcm_axi/tb
test -f ./lib_v4_on/libsyscverilated.a
env ENABLE_WAVES=no ULTRA_E_TCM_FOCUS=1 ULTRA_E_TCM_TRACE_LIMIT=20000 \
    ./build_v4_on/test_v4_on.x \
    -f /work/early_tcm_e_tcm_v4/short/build/etcm_probe.elf -r 0x2210 -c 2000 \
    > /followup/reports/early_tcm_e_tcm_v4/short_on_v4.log 2>&1
cat /followup/reports/early_tcm_e_tcm_v4/short_on_v4.log
grep -q 'ETCM_FOCUS signature.*status=PASS' /followup/reports/early_tcm_e_tcm_v4/short_on_v4.log
grep -q 'ETCM_FOCUS counts.*bad=0' /followup/reports/early_tcm_e_tcm_v4/short_on_v4.log
test ! -e verilator.vcd
test ! -e sysc_wave.vcd
'@
        Invoke-Ultra $cmd
    }
    'BoundedDiag' {
        $cmd = @'
set -e
cd /work/early_tcm_e_tcm_v4/top_tcm_axi/tb
test -x ./build_v4_on/test_v4_on.x
test -f ./lib_v4_on/libsyscverilated.a
test -f /work/benchmarks/coremark-ultra/build/xpack15.2-opt3-iter-516/coremark.elf
rm -f /followup/reports/early_tcm_e_tcm_v4/bounded_diag_v4_on.log
rm -f verilator.vcd sysc_wave.vcd
start_ns=$(date +%s%N)
set +e
env ENABLE_WAVES=no ULTRA_BOUNDED_DIAG=1 ULTRA_BOUNDED_DIAG_INTERVAL=100000 \
    /usr/bin/timeout --foreground 60s ./build_v4_on/test_v4_on.x \
    -f /work/benchmarks/coremark-ultra/build/xpack15.2-opt3-iter-516/coremark.elf \
    -r 0xffffffff -c 1000000 \
    > /followup/reports/early_tcm_e_tcm_v4/bounded_diag_v4_on.log 2>&1
rc=$?
end_ns=$(date +%s%N)
elapsed_ms=$(( (end_ns-start_ns)/1000000 ))
printf 'BOUNDED_DIAG_HOST_WALL_MS=%s\nBOUNDED_DIAG_COMMAND_EXIT=%s\n' "$elapsed_ms" "$rc" >> /followup/reports/early_tcm_e_tcm_v4/bounded_diag_v4_on.log
cat /followup/reports/early_tcm_e_tcm_v4/bounded_diag_v4_on.log
set -e
test "$rc" -eq 0
grep -q 'BOUNDED_DIAG exit=' /followup/reports/early_tcm_e_tcm_v4/bounded_diag_v4_on.log
test ! -e verilator.vcd
test ! -e sysc_wave.vcd
test ! -e /followup/reports/early_tcm_e_tcm_v4/verilator.vcd
test ! -e /followup/reports/early_tcm_e_tcm_v4/sysc_wave.vcd
'@
        Invoke-Ultra $cmd
    }
    'FullCoremark' {
        $cmd = @'
set -e
cd /work/early_tcm_e_tcm_v4/top_tcm_axi/tb
ELF=/work/benchmarks/coremark-ultra/build/xpack15.2-opt3-iter-516/coremark.elf
LOG=/followup/reports/early_tcm_e_tcm_v4/coremark_v4_on_full.log
SIG=/followup/reports/early_tcm_e_tcm_v4/coremark_v4_on_full.signature.bin
SIGTXT=/followup/reports/early_tcm_e_tcm_v4/coremark_v4_on_full.signature.txt
WITNESS=/followup/reports/early_tcm_e_tcm_v4/coremark_v4_on_full.witness.csv
test -x ./build_v4_on/test_v4_on.x
test -f ./lib_v4_on/libsyscverilated.a
test -f "$ELF"
ELF_SHA=$(sha256sum "$ELF" | awk '{print toupper($1)}')
test "$ELF_SHA" = "25F54F66915133DBA5A2FAA4DBDD246D7EA2C861459BEF8C9E4DA440DB73C6E5"
HALT_PC=$(riscv64-unknown-elf-nm "$ELF" | awk '$3=="_halt"{print "0x"$1;exit}')
SIG_START=$(riscv64-unknown-elf-nm "$ELF" | awk '$3=="__signature_start"{print "0x"$1;exit}')
SIG_END=$(riscv64-unknown-elf-nm "$ELF" | awk '$3=="__signature_end"{print "0x"$1;exit}')
test -n "$HALT_PC"
test -n "$SIG_START"
test -n "$SIG_END"
rm -f "$LOG" "$SIG" "$SIGTXT" "$WITNESS" verilator.vcd sysc_wave.vcd
set +e
ENABLE_WAVES=no ./build_v4_on/test_v4_on.x \
    -f "$ELF" -r "$HALT_PC" -p "$SIG" \
    -j __signature_start -k __signature_end > "$LOG" 2>&1
rc=$?
set -e
printf 'FULL_COREMARK_ELF_SHA256=%s\nFULL_COREMARK_HALT_PC=%s\nFULL_COREMARK_SIGNATURE_START=%s\nFULL_COREMARK_SIGNATURE_END=%s\nFULL_COREMARK_COMMAND_EXIT=%s\n' \
    "$ELF_SHA" "$HALT_PC" "$SIG_START" "$SIG_END" "$rc" >> "$LOG"
if test "$rc" -ne 0; then
    cat "$LOG"
    exit "$rc"
fi
test -s "$SIG"
strings -n 1 "$SIG" > "$SIGTXT"
test -s "$SIGTXT"
grep -Eiq 'seedcrc[[:space:]]*:[[:space:]]*0xe9f5' "$SIGTXT"
grep -Eiq 'crclist[[:space:]]*:[[:space:]]*0xe714' "$SIGTXT"
grep -Eiq 'crcmatrix[[:space:]]*:[[:space:]]*0x1fd7' "$SIGTXT"
grep -Eiq 'crcstate[[:space:]]*:[[:space:]]*0x8e3a' "$SIGTXT"
grep -Eiq 'crcfinal[[:space:]]*:[[:space:]]*0xe6dc' "$SIGTXT"
grep -Eq '^ *cycles[[:space:]]*:[[:space:]]*[0-9]+$' "$SIGTXT"
grep -Eq '^ *instructions retired[[:space:]]*:[[:space:]]*150778556$' "$SIGTXT"
if test -s scoreboard_witness.csv; then
    cp scoreboard_witness.csv "$WITNESS"
    test "$(wc -l < "$WITNESS")" -gt 1
fi
test -s "$WITNESS"
test ! -e verilator.vcd
test ! -e sysc_wave.vcd
cat "$LOG"
printf 'FULL_COREMARK status=PASS signature_crc=match retired=match cycles=observed witness=%s\n' \
    "$(test -s "$WITNESS" && echo present || echo absent)"
'@
        Invoke-Ultra $cmd
    }
}
