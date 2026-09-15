"""One-time curated snapshot builder. Sources read only; no measurements executed."""
from pathlib import Path
import json,shutil,hashlib
R=Path(__file__).resolve().parent.parent
A=R/'archives';F=R/'vivado/ultra_bht_btb_followup';S=F/'sim'
V4=S/'early_tcm_e_tcm_v4';SIMD=S/'ultra_simd_subset_v1';FOLLOW=SIMD/'coremark_followup'
source_names=['core_main.c','core_list_join.c','core_matrix.c','core_state.c','core_util.c','core_portme.c','ee_printf.c','coremark.h','core_portme.h','startup.S','linker.ld']

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def jsonfile(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def copy(src,dst):
    assert src.is_file(),src
    dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)

common=A/'common';common.mkdir(exist_ok=True)
for p in (V4/'isa_sim').iterdir():
    if p.is_file() and (p.suffix in ['.h','.cpp','.c'] or p.name in ['makefile','README.md','LICENSE']):copy(p,common/'isa_sim'/p.name)
copy(R/'runs/ultra-top-tcm-bht-btb/LICENSE',common/'ULTRA_LICENSE')
jsonfile(common/'manifest.json',[dict(file=p.relative_to(common).as_posix(),sha256=digest(p)) for p in sorted(common.rglob('*')) if p.is_file() and p.name!='manifest.json'])

for name,origin,is_simd in [('ultra-v4-c',V4,False),('ultra-v4-simd-edap2',SIMD,True)]:
    dst=A/'2026-09-16'/name
    if dst.exists():raise SystemExit('Refusing existing snapshot '+str(dst))
    dst.mkdir(parents=True);provenance=[]
    def take(src,relative):
        target=dst/relative;copy(src,target)
        provenance.append(dict(file=relative,source=src.relative_to(R).as_posix(),source_sha256=digest(src)))
    for tree in ['core/riscv','top_tcm_axi/src_v']:
        for p in sorted((origin/tree).rglob('*')):
            if p.is_file() and p.suffix in ['.v','.vh','.sv']:
                take(p,'rtl/'+p.relative_to(origin).as_posix())
    for p in (origin/'top_tcm_axi/tb').iterdir():
        if p.is_file() and (p.suffix in ['.cpp','.h','.inc'] or p.name.startswith('makefile')):
            take(p,'simulation/tb/'+p.name)
    software=FOLLOW/'EDAP2/source' if is_simd else S/'compiler_screen_20260915/source/coremark-ultra'
    for f in source_names+(['xsimd.h','encoding.h'] if is_simd else []):take(software/f,'software/'+f)
    take(R/'runs/ultra-top-tcm-bht-btb/LICENSE','LICENSE')
    take(F/'rtl/ultra_top_tcm_80MHz.xdc','constraints/clock_80MHz.xdc')
    params=dict(EXTRA_DECODE_STAGE=1,SUPPORT_REGFILE_XILINX=1,SUPPORT_BRANCH_PREDICTION=1,SUPPORT_EARLY_TCM_LOAD=1)
    cfg=dict(name=name,archive_date='2026-09-16',original_source=origin.relative_to(R).as_posix(),top='riscv_tcm_top',part='xc7z020clg400-1',clock_ns=12.5,tcm_bytes=65536,boot_vector='0x2000',btb_entries=64,btb_tag='full PC tag',ras=False,top_parameters=params,compiler='xPack riscv-none-elf-gcc 15.2.0-1',architecture='rv32im_zicsr',abi='ilp32',optimization=['-O3','-flto','-funroll-loops'],vivado='2022.2',docker_image='ultra-top-tcm:verilator-5.050-systemc-2.3.1a',container='ultra-top-tcm-dev',official_10_second_result=False,accepted_D1_replaced=False)
    if is_simd:
        params.update({x:1 for x in ['SUPPORT_XBEXTU','SUPPORT_XPACK16','SUPPORT_XDOT2H','SUPPORT_XADD16']})
        cfg.update(status='SHORT_COREMARK_AND_80MHZ_OOC_PASS_NOT_FULL_BASELINE',iterations=16,cycles=4799009,retired=4198728,cm_per_mhz=16e6/4799009,full_516='NOT_RUN',lut=3939,ff=1910,dsp=6,bram36=16,wns_ns=.013,tns_ns=0,whs_ns=.052,software='EDAP2: custom intrinsics, fresh 288B packing, two-output matrix; modified benchmark experiment',deferred=['516 iteration run','new-instruction targeted squash writeback suppression evidence'])
        for f in ['coremark.elf','build.log','sections.txt','symbols.txt','manifest.json']:take(FOLLOW/'EDAP2/build'/f,'evidence/software/'+f)
        for f in ['run.log','signature.bin','signature.txt','metrics.json']:take(FOLLOW/'EDAP2/results'/f,'evidence/coremark_short/'+f)
        for f in ['report.md','results.csv']:take(FOLLOW/f,'evidence/'+f)
        for f in ['summary.json','function_summary.csv','checks.txt','run.log']:take(FOLLOW/'EDAP2/profile'/f,'evidence/profile/'+f)
        for f in ['timing_summary.rpt','critical_paths.rpt','utilization.rpt','utilization_hierarchical.rpt','drc.rpt','check_timing.rpt','contract.txt','before_dot_paths.rpt']:take(FOLLOW/'physical_followup'/f,'evidence/ppa/'+f)
        take(FOLLOW/'physical_followup.log','evidence/ppa/physical_followup.log')
        take(SIMD/'build/vivado_ppa_12p5/simd_subset_v1_route_timing_summary.rpt','evidence/ppa/before_physical_timing.rpt')
        for f in ['build.py','run.sh','prepare_profile.py','profile.sh','analyze.py','physical_followup.tcl']:take(FOLLOW/f,'provenance_scripts/'+f)
        for f in ['run_rtl_candidate.sh','run_rtl_candidate.ps1','implement_simd_subset_v1_ooc.tcl']:take(SIMD/'scripts'/f,'provenance_scripts/'+f)
        for p in (SIMD/'tests').iterdir():
            if p.is_file() and p.suffix in ['.sv','.S']:take(p,'tests/'+p.name)
        take(SIMD/'build/units_run.log','evidence/functional/units_run.log')
        take(SIMD/'build/results/all/integration.log','evidence/functional/integration.log')
        take(SIMD/'build/results/all/integration.signature.bin','evidence/functional/integration.signature.bin')
        take(SIMD/'software/encoding.json','software/encoding.json')
        take(FOLLOW/'EDAP2/software.diff','evidence/software/software.diff')
        desc='四指令SIMD＋EDAP2归档。16次完整算法短测4799009cycles、3.334021670CM/MHz，五项CRC通过。516次尚未执行；保留为独立候选，不自动替换accepted基线。'
    else:
        cfg.update(status='BEST_MEASURED_PRE_SIMD_V4_C_ARCHIVE',iterations=516,cycles=167246919,retired=148000698,cm_per_mhz=516e6/167246919,short_iterations=16,short_cycles=5186392,lut=3689,ff=1910,dsp=4,bram36=16,wns_ns=0,tns_ns=0,whs_ns=.042,software='C optimization; original benchmark algorithm sources unchanged')
        for kind in ['full','short']:
            for f in ['coremark.elf','build.log','sections.txt','symbols.txt']:
                take(S/'compiler_screen_20260915/build'/kind/'C'/f,'evidence/software_'+kind+'/'+f)
            for ext in ['log','signature.bin','signature.txt']:
                take(F/'reports/compiler_screen_20260915'/f'{kind}_C.{ext}',f'evidence/coremark_{kind}/{kind}_C.{ext}')
        for f in ['compiler_screen_report.md','compiler_screen_results.csv']:take(F/'reports/compiler_screen_20260915'/f,'evidence/'+f)
        pp=F/'reports/early_tcm_e_tcm_v4/vivado_post_v4'
        for f in ['e_tcm_v4_routed_timing_summary.rpt','e_tcm_v4_routed_utilization.rpt','e_tcm_v4_routed_utilization_hierarchical.rpt','e_tcm_v4_routed_drc.rpt','e_tcm_v4_routed_check_timing.rpt','e_tcm_v4_routed_critical_paths.rpt','routed_manifest.txt']:take(pp/f,'evidence/ppa/'+f)
        for f in ['fetch_recovery.log','short_off_v4.log','short_on_v4.log']:take(F/'reports/early_tcm_e_tcm_v4'/f,'evidence/functional/'+f)
        take(F/'scripts/run_compiler_screen_20260915.ps1','provenance_scripts/run_compiler_screen_20260915.ps1')
        for f in ['run_v4.ps1','implement_e_tcm_v4_ooc.tcl']:take(F/'scripts/early_tcm_e_tcm_v4'/f,'provenance_scripts/'+f)
        desc='SIMD引入前，兼顾80MHz时序与资源的最佳已测组合：E-TCM v4＋C编译选项。516次167246919cycles、3.085258629CM/MHz，CRC通过；保存原始16次对照便于与SIMD公平比较。'
    jsonfile(dst/'config.json',cfg)
    (dst/'README.md').write_text('# '+name+'\n\n'+desc+'\n\n配置见[config.json](config.json)，独立RTL在`rtl/`，原软件源在`software/`，实测ELF、日志和时序在`evidence/`。顶层参数必须显式使用config.json中的值；源码默认值不代表实验开关。\n\n所有性能为周期换算，不是正式10秒成绩或板级Fmax。SIMD版不能沿用标量版516次结果。历史脚本路径仅用于追溯，恢复到新目录后需要调整路径；见[归档总说明](../../README.md)。\n\n本次只复制/校验既有文件，没有重跑仿真或实现。manifest.json记录精确字节哈希及来源。保留原许可证，波形、编译缓存、工具、DCP和bitstream未归档。\n',encoding='utf-8')
    jsonfile(dst/'manifest.json',dict(files=[dict(file=p.relative_to(dst).as_posix(),bytes=p.stat().st_size,sha256=digest(p)) for p in sorted(dst.rglob('*')) if p.is_file()],origins=provenance))
    print(name,'files',len(provenance),'bytes',sum(p.stat().st_size for p in dst.rglob('*') if p.is_file()))
