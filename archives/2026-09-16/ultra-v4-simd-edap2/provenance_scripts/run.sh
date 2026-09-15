#!/bin/bash
set -euo pipefail
root=/work/ultra_simd_subset_v1/coremark_followup
v=${1:?variant}
case "$v" in E) group=e;; EDAP|EDAP2|SP2) group=all;; *) exit 2;; esac
out="$root/$v/results"
mkdir -p "$out"
cd "$out"
elf="$root/$v/build/coremark.elf"
halt=0x$(riscv64-unknown-elf-nm "$elf" | awk '$3=="_halt"{print $1;exit}')
test ! -e run.log
env -u ULTRA_V4_CORRECTED_OBS -u ULTRA_V4_SHARED_OBS -u ULTRA_EARLY_TCM_TRACE ENABLE_WAVES=no \
 timeout --foreground 180s /work/ultra_simd_subset_v1/build/sim_$group/ultra_simd_$group.x \
 -f "$elf" -r "$halt" -p signature.bin -j __signature_start -k __signature_end -c 15000000 > run.log 2>&1
python3 - <<'PY'
import re,pathlib,json
p=pathlib.Path('signature.bin');text=p.read_bytes().split(b'\0',1)[0].decode()
pathlib.Path('signature.txt').write_text(text)
crc=dict(re.findall(r'(seedcrc|crclist|crcmatrix|crcstate|crcfinal)\s*:\s*0x([0-9a-f]+)',text))
assert crc==dict(seedcrc='e9f5',crclist='e714',crcmatrix='1fd7',crcstate='8e3a',crcfinal='dd50'),crc
metrics={}
for k,pat in [('cycles',r'^cycles\s*:\s*(\d+)'),('retired',r'^instructions retired:\s*(\d+)'),('scoreboard',r'^scoreboard_stall_cycles\s*:\s*(\d+)'),('branch_flush',r'^branch_flush_cycles\s*:\s*(\d+)'),('branch_request',r'^branch_request_events\s*:\s*(\d+)')]:
 m=re.search(pat,text,re.M);assert m,k;metrics[k]=int(m[1])
metrics['cm_per_mhz']=16000000/metrics['cycles'];metrics['crc']=crc
pathlib.Path('metrics.json').write_text(json.dumps(metrics,indent=2))
print('CRC PASS',json.dumps(metrics))
PY
test ! -e verilator.vcd
test ! -e sysc_wave.vcd
