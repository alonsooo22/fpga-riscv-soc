"""Isolated full-algorithm, short-workload SIMD experiment. No RTL changes."""
from pathlib import Path
import subprocess, shutil, sys, json, hashlib, difflib

ROOT=Path(__file__).resolve().parent
CAND=ROOT.parent
BASE=CAND.parent/'compiler_screen_20260915/source/coremark-ultra'
TOOLS=Path('D:/code/FPGA/toolchains/xpack-riscv-none-elf-gcc-15.2.0-1/bin')
names=['core_main.c','core_list_join.c','core_matrix.c','core_state.c','core_util.c','core_portme.c','ee_printf.c','coremark.h','core_portme.h','startup.S','linker.ld']

def replace_body(text,name,body):
    import re
    m=re.search(r'\nvoid\s*\n'+name+r'\([^;]+?\)\s*\{',text)
    assert m,name
    start=m.end()-1; end=start+1; depth=1
    while depth:
        depth+=(text[end]=='{')-(text[end]=='}'); end+=1
    return text[:start]+'{\n'+body+'\n}'+text[end:]

def prepare(variant):
    src=ROOT/variant/'source'; src.mkdir(parents=True,exist_ok=True)
    for name in names: shutil.copy2(BASE/name,src/name)
    for name in ['xsimd.h','encoding.h']:shutil.copy2(CAND/'software'/name,src/name)
    original=(src/'core_matrix.c').read_text()
    code=original.replace('#include "coremark.h"','#include "coremark.h"\n#include "xsimd.h"')
    code=code.replace('#define bit_extract(x, from, to) (((x) >> (from)) & (~(0xffffffff << (to))))','#define bit_extract(x, from, to) xs_extract((x),(from),(to))')
    if variant!='E':
        code=code.replace('/* Function: core_bench_matrix','// Fresh per-call packing; 288 B; no reuse across mutable inputs.\nstatic ee_u32 simd_ap[9][4], simd_bp[9][4];\ntypedef ee_u32 simd_alias32 __attribute__((may_alias));\n\n/* Function: core_bench_matrix',1)
        code=replace_body(code,'matrix_add_const','''    ee_u32 count=N*N, i=0;
    if (count && ((ee_ptr_int)A & 3u)) { A[0]+=val; i=1; }
    ee_u32 vv=xs_pack((ee_u16)val,(ee_u16)val);
    for (;i+1<count;i+=2) { simd_alias32 *p=(simd_alias32 *)(A+i); *p=xs_add(*p,vv); }
    if(i<count) A[i]+=val;''')
        prefix='''    if(N!=9) {
        for(ee_u32 i=0;i<N;i++)for(ee_u32 j=0;j<N;j++){
            ee_u32 s=0;for(ee_u32 k=0;k<N;k++)s+=(ee_u32)((MATRES)A[i*N+k]*(MATRES)B[k*N+j]);C[i*N+j]=(MATRES)s;
        } return;
    }
    for(ee_u32 i=0;i<9;i++)for(ee_u32 k=0;k<4;k++){
        simd_ap[i][k]=xs_pack((ee_u16)A[i*9+2*k],(ee_u16)A[i*9+2*k+1]);
        simd_bp[i][k]=xs_pack((ee_u16)B[2*k*9+i],(ee_u16)B[(2*k+1)*9+i]);
    }
'''
        plain='''    for(ee_u32 i=0;i<9;i++)for(ee_u32 j=0;j<9;j++){
        ee_u32 s=0;for(ee_u32 k=0;k<4;k++)s+=xs_dot(simd_ap[i][k],simd_bp[j][k]);
        s+=(ee_u32)((MATRES)A[i*9+8]*(MATRES)B[8*9+j]); C[i*9+j]=(MATRES)s;
    }'''
        block='''    for(ee_u32 i=0;i<9;i++){
        ee_u32 j=0;
        for(;j+1<9;j+=2){
            ee_u32 s0=0,s1=0;
            for(ee_u32 k=0;k<4;k++){
                ee_u32 pa=simd_ap[i][k];
                s0+=xs_dot(pa,simd_bp[j][k]);
                s1+=xs_dot(pa,simd_bp[j+1][k]);
            }
            MATRES tail=A[i*9+8];
            s0+=(ee_u32)(tail*(MATRES)B[8*9+j]);
            s1+=(ee_u32)(tail*(MATRES)B[8*9+j+1]);
            C[i*9+j]=(MATRES)s0; C[i*9+j+1]=(MATRES)s1;
        }
        ee_u32 s=0;for(ee_u32 k=0;k<4;k++)s+=xs_dot(simd_ap[i][k],simd_bp[j][k]);
        s+=(ee_u32)((MATRES)A[i*9+8]*(MATRES)B[8*9+j]);C[i*9+j]=(MATRES)s;
    }'''
        code=replace_body(code,'matrix_mul_matrix',prefix+(block if variant in ['EDAP2','SP2'] else plain))
    (src/'core_matrix.c').write_text(code)
    (ROOT/variant/'software.diff').write_text(''.join(difflib.unified_diff(original.splitlines(True),code.splitlines(True),fromfile='original/core_matrix.c',tofile=variant+'/core_matrix.c')))
    return src

def build(variant):
    src=prepare(variant);out=ROOT/variant/'build';out.mkdir(exist_ok=True)
    flags=['-march=rv32im_zicsr','-mabi=ilp32','-mcmodel=medany','-msmall-data-limit=0','-ffreestanding','-fno-builtin','-fno-stack-protector','-fno-pic','-fdata-sections','-ffunction-sections','-std=gnu11','-Wall','-Wextra','-I'+str(src),'-DTOTAL_DATA_SIZE=2000','-DMEM_METHOD=MEM_STATIC','-DMULTITHREAD=1','-DITERATIONS=16','-DHAS_FLOAT=0','-DHAS_STDIO=0','-DHAS_PRINTF=0','-DMAIN_HAS_NOARGC=1','-DMAIN_HAS_NORETURN=0','-DSEED_METHOD=SEED_VOLATILE','-DMEM_LOCATION="TCM"','-DULTRA_OPT_LEVEL=3','-DULTRA_PERF_COUNTERS','-DULTRA_XPACK_GCC','-O3','-flto','-funroll-loops','-g']
    if variant=='SP2':flags+=['-DXSIMD_MODEL']
    log=[]
    def run(args):
        p=subprocess.run([str(x) for x in args],capture_output=True,text=True)
        log.append(subprocess.list2cmdline([str(x) for x in args])+'\n'+p.stdout+p.stderr)
        (out/'build.log').write_text('\n'.join(log))
        if p.returncode:raise RuntimeError(log[-1])
        return p.stdout
    gcc=TOOLS/'riscv-none-elf-gcc.exe';objs=[]
    for f in names:
        if not f.endswith(('.c','.S')):continue
        obj=out/(Path(f).stem+'.o');run([gcc,*flags,'-c',src/f,'-o',obj]);objs.append(obj)
    elf=out/'coremark.elf'
    run([gcc,*flags,'-nostdlib','-Wl,--gc-sections','-Wl,-T,'+str(src/'linker.ld'),'-Wl,-Map,'+str(out/'coremark.map'),*objs,'-lgcc','-o',elf])
    for tool,arg,name in [('objdump','-d','coremark.dis'),('nm','-n','symbols.txt'),('size','-A','sections.txt')]:
        (out/name).write_text(run([TOOLS/f'riscv-none-elf-{tool}.exe',arg,elf]))
    (out/'manifest.json').write_text(json.dumps(dict(variant=variant,iterations=16,elf_sha256=hashlib.sha256(elf.read_bytes()).hexdigest(),flags=flags),indent=2))
    print('BUILD PASS',variant,flush=True)

if __name__=='__main__':
    for v in sys.argv[1:]:
        assert v in ['E','EDAP','EDAP2','SP2'];build(v)
