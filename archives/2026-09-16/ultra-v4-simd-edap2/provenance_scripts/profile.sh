#!/bin/bash
set -euo pipefail
root=/work/ultra_simd_subset_v1/coremark_followup
c=/work/ultra_simd_subset_v1
isa=/work/early_tcm_e_tcm_v4/isa_sim
cd "$root"
if test "${1:-}" = Build; then
 g++ -fpic -O2 -std=c++17 -DVM_TRACE=1 -Iprofile_tb -I"$c/build/rtl_model_all" -I"$isa" -I/usr/local/share/verilator/include -I/usr/local/share/verilator/include/vltstd -I/usr/local/systemc-2.3.1/include -c profile_tb/main.cpp -o profile_main.o > profile_build.log 2>&1
 g++ -O2 profile_main.o "$c/build/obj_tb_all/riscv_tcm_top_rtl.o" -L/usr/local/systemc-2.3.1/lib-linux64 -L"$isa" -Wl,-rpath,/usr/local/systemc-2.3.1/lib-linux64 -o profile.x -lsystemc -lisa_sim "$c/build/lib_model_all/libsyscverilated.a" -lelf -lbfd >> profile_build.log 2>&1
 echo PROFILE_BUILD_PASS
 exit
fi
v=${1:?variant}
case "$v" in EDAP|EDAP2) loop=0x9f20;; *) exit 2;; esac
out="$root/$v/profile"
mkdir -p "$out"
test ! -e "$out/run.log"
env -u ULTRA_V4_CORRECTED_OBS -u ULTRA_V4_SHARED_OBS -u ULTRA_EARLY_TCM_TRACE ENABLE_WAVES=no SIMD_LOOP_PC="$loop" SIMD_PROFILE_DIR="$out/" \
 timeout --foreground 90s ./profile.x -f "$root/$v/build/coremark.elf" -r 0x202c -c 2000000 > "$out/run.log" 2>&1
grep 'PROFILE_' "$out/run.log"
grep -q 'PROFILE_CLOSURE status=PASS' "$out/run.log"
test ! -e verilator.vcd
test ! -e sysc_wave.vcd
