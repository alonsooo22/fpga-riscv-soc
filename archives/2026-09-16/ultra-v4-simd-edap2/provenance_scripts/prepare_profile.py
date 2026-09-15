from pathlib import Path
import shutil
r=Path(__file__).resolve().parent;c=r.parent
tb=r/'profile_tb';tb.mkdir(exist_ok=True)
for f in (c/'top_tcm_axi/tb').iterdir():
    if f.suffix in ['.h','.cpp']:shutil.copy2(f,tb/f.name)
source=(c.parents[1]/'scripts/profile_c_vector/vector_profile.inc').read_text()
source=source.replace('uint32_t opcode=0, last_addr=0;', 'uint64_t stack_mem=0, sp_base_mem=0; uint32_t opcode=0, last_addr=0;')
source=source.replace('uint32_t vp_iter=0, vp_last_pc=0;', 'uint32_t vp_iter=1, vp_last_pc=0; uint32_t vp_min_sp=0x10000;')
source=source.replace('// Verified C ELF: first timed iteration starts at 0x91f4; subsequent ones at 0x96b8.', '// Fixed nonzero iterations: loop target is entered first at iteration 2. Bound per ELF disassembly.')
source=source.replace('(pc==0x91f4u || pc==0x96b8u)', '(pc==std::strtoul(std::getenv("SIMD_LOOP_PC"),nullptr,0))')
source=source.replace('++s.mem;', '++s.mem; s.stack_mem += address>=0xf000u && address<0x10000u; s.sp_base_mem += rs1==2; if(rs1==2 && a<vp_min_sp)vp_min_sp=a;')
source=source.replace('major==115);', 'major==115 || major==11);')
source=source.replace('const char *dir="/followup/reports/profile_c_vector_20260915/";', 'const char *dir=std::getenv("SIMD_PROFILE_DIR");')
source=source.replace('taken,not_taken\\n','taken,not_taken,stack_memory_ops,sp_base_memory_ops\\n')
source=source.replace('%llu,%llu\\n",kv.first', '%llu,%llu,%llu,%llu\\n",kv.first')
source=source.replace('(unsigned long long)s.not_taken);','(unsigned long long)s.not_taken,(unsigned long long)s.stack_mem,(unsigned long long)s.sp_base_mem);')
source=source.replace('if(!ok)m_closure_failure=true;','std::printf("PROFILE_STACK_MIN_BASE=0x%08x (observed memory bases, not proof of all stack writes)\\n",vp_min_sp);\n    if(!ok)m_closure_failure=true;')
(tb/'vector_profile.inc').write_text(source)
h=(tb/'testbench.h').read_text()
for a,b in [
 ('    void step(void)','    #include "vector_profile.inc"\n    void step(void)'),
 ('        drive_irq_script();','        vector_profile_sample();\n        drive_irq_script();'),
 ('return (m_early_observer_enabled && m_early_stop_requested)','return vp_done || (m_early_observer_enabled && m_early_stop_requested)'),
 ('        v4_shared_report();','        vector_profile_report();\n        v4_shared_report();')]:
    assert a in h,a;h=h.replace(a,b)
(tb/'testbench.h').write_text(h)
print('PROFILE HARNESS PREPARED; RTL model unchanged')
