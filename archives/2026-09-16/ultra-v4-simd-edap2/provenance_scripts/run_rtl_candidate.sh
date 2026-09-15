#!/usr/bin/env bash
set -euo pipefail

ROOT=/work/ultra_simd_subset_v1
OLD=/work/early_tcm_e_tcm_v4

feature_params() {
    case "$1" in
        ALL) echo '-GSUPPORT_XBEXTU=1 -GSUPPORT_XPACK16=1 -GSUPPORT_XDOT2H=1 -GSUPPORT_XADD16=1' ;;
        E)   echo '-GSUPPORT_XBEXTU=1 -GSUPPORT_XPACK16=0 -GSUPPORT_XDOT2H=0 -GSUPPORT_XADD16=0' ;;
        D)   echo '-GSUPPORT_XBEXTU=0 -GSUPPORT_XPACK16=1 -GSUPPORT_XDOT2H=1 -GSUPPORT_XADD16=0' ;;
        A)   echo '-GSUPPORT_XBEXTU=0 -GSUPPORT_XPACK16=1 -GSUPPORT_XDOT2H=0 -GSUPPORT_XADD16=1' ;;
        *)   echo "unknown model group: $1" >&2; return 2 ;;
    esac
}

build_model() {
    local group="$1" tag="${1,,}" params log ec
    params="$(feature_params "$group")"
    log="$ROOT/build/model_${tag}_build.log"
    mkdir -p "$ROOT/build"
    set +e
    (
        set -e
        cd "$ROOT/top_tcm_axi/tb"
        make -B -f makefile.generate_verilated CORE=riscv \
            OUTPUT_DIR="../../build/rtl_model_${tag}/" \
            VERILATE_PARAMS="--trace -Wno-fatal -DULTRA_PERF_COUNTERS -DULTRA_SCOREBOARD_TRACE -GSUPPORT_BRANCH_PREDICTION=1 -GEXTRA_DECODE_STAGE=1 -GSUPPORT_REGFILE_XILINX=1 -GSUPPORT_EARLY_TCM_LOAD=1 $params" \
            VERILATOR_OPTS="--pins-sc-uint --l2-name v --Wno-fatal"
        make -B -f makefile.build_verilated \
            SRC_DIR="../../build/rtl_model_${tag}/" \
            OBJ_DIR="../../build/obj_model_${tag}/" \
            LIB_DIR="../../build/lib_model_${tag}/"
        make -B -f makefile.build_sysc_tb \
            VERILATED_DIR="../../build/rtl_model_${tag}/" \
            OBJ_DIR="../../build/obj_tb_${tag}/" \
            EXE_DIR="../../build/sim_${tag}/" \
            TARGET="ultra_simd_${tag}.x" \
            SRC_DIR=. \
            CFLAGS="-fpic -O2 -std=c++17 -DVM_TRACE=1 -I$ROOT/top_tcm_axi/tb -I$ROOT/build/rtl_model_${tag} -I$OLD/isa_sim -I/usr/local/share/verilator/include -I/usr/local/share/verilator/include/vltstd -I/usr/local/systemc-2.3.1/include" \
            LIB_PATH="$ROOT/build/lib_model_${tag}/ $OLD/isa_sim"
        test -x "../../build/sim_${tag}/ultra_simd_${tag}.x"
    ) >"$log" 2>&1
    ec=$?
    set -e
    tail -n 24 "$log"
    printf 'MODEL_BUILD_EXIT=%s MODEL=%s LOG=%s\n' "$ec" "$group" "$log"
    return "$ec"
}

run_integration() {
    local group="$1" tag="${1,,}" sim elf done_pc out sig log ec
    sim="$ROOT/build/sim_${tag}/ultra_simd_${tag}.x"
    elf="$ROOT/build/integration/integration.elf"
    done_pc="0x$(riscv64-unknown-elf-nm "$elf" | awk '$3=="done"{print $1; exit}')"
    test -x "$sim"
    test -f "$elf"
    test -n "$done_pc"
    out="$ROOT/build/results/$tag"
    mkdir -p "$out"
    sig="$out/integration.signature.bin"
    log="$out/integration.log"
    rm -f "$sig" "$log"
    set +e
    ENABLE_WAVES=no ULTRA_BOUNDED_DIAG=1 "$sim" -f "$elf" -r "$done_pc" \
        -p "$sig" -j __signature_start -k __signature_end -c 1000000 >"$log" 2>&1
    ec=$?
    set -e
    printf 'SIM_EXIT=%s STOP_PC=%s MODEL=%s\n' "$ec" "$done_pc" "$group" >>"$log"
    tail -n 28 "$log"
    test "$ec" -eq 0
    test -s "$sig"
    python3 -c 'import struct,sys; w=struct.unpack("<2I",open(sys.argv[1],"rb").read(8)); print("INTEGRATION_SIGNATURE words=%08x,%08x" % w); sys.exit(0 if w==(0x50415353,2) else 1)' "$sig"
    printf 'INTEGRATION_DONE MODEL=%s SIGNATURE=%s LOG=%s\n' "$group" "$sig" "$log"
}

run_kernel() {
    local model="$1" software="$2" tag="${1,,}" sim elf sym halt_pc out sig log siglog ec
    sim="$ROOT/build/sim_${tag}/ultra_simd_${tag}.x"
    elf="$ROOT/build/$software/kernel.elf"
    sym="$ROOT/build/$software/symbols.txt"
    test -x "$sim"
    test -f "$elf"
    test -f "$sym"
    halt_pc="0x$(awk '/[[:space:]]_halt[[:space:]]*$/{print $1; exit}' "$sym")"
    test -n "$halt_pc"
    out="$ROOT/build/results/$tag"
    mkdir -p "$out"
    sig="$out/kernel_${software}.signature.bin"
    log="$out/kernel_${software}.log"
    siglog="$out/kernel_${software}.signature.txt"
    rm -f "$sig" "$log" "$siglog"
    set +e
    ENABLE_WAVES=no ULTRA_BOUNDED_DIAG=1 "$sim" -f "$elf" -r "$halt_pc" \
        -p "$sig" -j __signature_start -k __signature_end -c 1000000 >"$log" 2>&1
    ec=$?
    set -e
    printf 'SIM_EXIT=%s HALT_PC=%s MODEL=%s SOFTWARE=%s\n' "$ec" "$halt_pc" "$model" "$software" >>"$log"
    tail -n 18 "$log"
    test "$ec" -eq 0
    test -s "$sig"
    python3 "$ROOT/scripts/check_signature.py" "$sig" >"$siglog" 2>&1
    cat "$siglog"
    printf 'KERNEL_DONE MODEL=%s SOFTWARE=%s SIGNATURE=%s LOG=%s\n' "$model" "$software" "$sig" "$log"
}

run_reference_r() {
    local sim="$OLD/top_tcm_axi/tb/build_v4_on/test_v4_on.x"
    local elf="$ROOT/build/R/kernel.elf"
    local sym="$ROOT/build/R/symbols.txt"
    local halt_pc="0x$(awk '/[[:space:]]_halt[[:space:]]*$/{print $1; exit}' "$sym")"
    local out="$ROOT/build/results/reference_r"
    local sig="$out/kernel_R.signature.bin"
    local log="$out/kernel_R.log"
    local siglog="$out/kernel_R.signature.txt"
    local ec
    test -x "$sim"
    test -f "$elf"
    test -n "$halt_pc"
    mkdir -p "$out"
    rm -f "$sig" "$log" "$siglog"
    set +e
    ENABLE_WAVES=no ULTRA_BOUNDED_DIAG=1 "$sim" -f "$elf" -r "$halt_pc" \
        -p "$sig" -j __signature_start -k __signature_end -c 1000000 >"$log" 2>&1
    ec=$?
    set -e
    printf 'SIM_EXIT=%s HALT_PC=%s MODEL=reference_v4_on SOFTWARE=R\n' "$ec" "$halt_pc" >>"$log"
    tail -n 18 "$log"
    test "$ec" -eq 0
    test -s "$sig"
    python3 "$ROOT/scripts/check_signature.py" "$sig" >"$siglog" 2>&1
    cat "$siglog"
    printf 'KERNEL_DONE MODEL=reference_v4_on SOFTWARE=R SIGNATURE=%s LOG=%s\n' "$sig" "$log"
}

case "${1:-}" in
    BuildModel) build_model "${2:-ALL}" ;;
    RunIntegration) run_integration "${2:-ALL}" ;;
    RunKernel) run_kernel "${2:-ALL}" "${3:-E}" ;;
    RunKernelSet)
        for software in E D DP A EDA EDAP; do run_kernel "${2:-ALL}" "$software"; done
        ;;
    RunReferenceR) run_reference_r ;;
    *) echo 'usage: run_rtl_candidate.sh BuildModel|RunIntegration|RunKernel|RunKernelSet|RunReferenceR [ALL|E|D|A] [software]' >&2; exit 2 ;;
esac
