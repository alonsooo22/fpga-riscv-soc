from pathlib import Path
import csv,json,collections,re,subprocess
R=Path(__file__).resolve().parent
tools=Path('D:/code/FPGA/toolchains/xpack-riscv-none-elf-gcc-15.2.0-1/bin')

def kind(op):
    major=op&127;f=(op>>12)&7
    if major==11:return ['xbextu','xpack16','xdot2h','xadd16'][f] if f<4 else 'custom_other'
    if major==3:return ['lb','lh','lw','load3','lbu','lhu','load6','load7'][f]
    if major==35:return ['sb','sh','sw','store3','store4','store5','store6','store7'][f]
    if major==51 and op>>25==1:return ['mul','mulh','mulhsu','mulhu','div','divu','rem','remu'][f]
    return {99:'branch',111:'jal',103:'jalr',19:'alu_imm',51:'alu_reg',55:'lui',23:'auipc',115:'system'}.get(major,'other')

def output(path,rows):
    keys=list(dict.fromkeys(k for r in rows for k in r))
    with path.open('w',newline='') as f:
        w=csv.DictWriter(f,keys);w.writeheader();w.writerows(rows)

def profile(v):
    p=R/v/'profile';build=R/v/'build'
    rows=list(csv.DictReader((p/'pc_profile.csv').open()))
    addresses='\n'.join('0x'+row['pc'] for row in rows)+'\n'
    run=subprocess.run([str(tools/'riscv-none-elf-addr2line.exe'),'-a','-f','-i','-e',str(build/'coremark.elf')],input=addresses,capture_output=True,text=True,check=True)
    (p/'pc_source_mapping.txt').write_text(run.stdout)
    parts=re.split(r'(?m)^(0x[0-9a-f]+)\s*$',run.stdout);mapping={}
    for i in range(1,len(parts),2):
        lines=[s.strip() for s in parts[i+1].splitlines() if s.strip()]
        mapping[int(parts[i],16)]=list(zip(lines[::2],lines[1::2]))
    dis={int(a,16):int(b,16) for a,b in re.findall(r'^\s*([0-9a-f]+):\s+([0-9a-f]{8})\s',(build/'coremark.dis').read_text(),re.M)}
    fun=collections.defaultdict(collections.Counter);groups=collections.defaultdict(collections.Counter);inst=collections.Counter();annotated=[]
    for row in rows:
        pc=int(row['pc'],16);op=int(row['opcode'],16);n={k:int(v) for k,v in row.items() if k not in ['pc','opcode']}
        if n['retired']:assert dis[pc]==op,(v,hex(pc))
        frames=mapping[pc];eligible=[f for f in frames if not f[0].startswith('xs_')]
        name,loc=eligible[0] if eligible else frames[0]
        assert name!='??',(v,hex(pc))
        file=re.search(r'(core_\w+\.c):',loc)
        category={'core_util.c':'CRC','core_matrix.c':'matrix','core_state.c':'state','core_list_join.c':'list','core_main.c':'framework'}.get(file[1] if file else '', 'other')
        t=kind(op)
        for b in [fun[name],groups[category]]:b.update(n);b['instruction_'+t]+=n['retired']
        inst[t]+=n['retired'];annotated.append(dict(row,function=name,category=category,location=loc,instruction=t))
    log=(p/'run.log').read_text();m=re.search(r'PROFILE_CLOSURE status=PASS start=(\d+) end=(\d+) cycles=(\d+) retired=(\d+)',log);assert m
    assert sum(r['residency_cycles'] for r in fun.values())==int(m[3])
    assert sum(inst.values())==int(m[4])
    summary=dict(cycles=int(m[3]),retired=int(m[4]),functions=fun,categories=groups,instructions=inst)
    (p/'summary.json').write_text(json.dumps(summary,indent=2))
    output(p/'function_summary.csv',[dict(function=k,**s) for k,s in sorted(fun.items(),key=lambda kv:-kv[1]['residency_cycles'])])
    output(p/'pc_annotated.csv',annotated)
    (p/'checks.txt').write_text('PASS all retired opcodes match actual ELF\nPASS no unmapped PCs\nPASS residency and retirement sums\nROI iteration 3-4; source mapping follows inlined call frames; not causal cycle attribution\n')
    print(v,'cycles',summary['cycles'],'retired',summary['retired'],'instructions',dict(inst))
    for name,s in sorted(fun.items(),key=lambda kv:-kv[1]['residency_cycles'])[:18]:
        print(name,'cycles',s['residency_cycles'],'ret',s['retired'],'load',sum(s['instruction_'+x] for x in ['lb','lh','lw','lbu','lhu']),'store',sum(s['instruction_'+x] for x in ['sb','sh','sw']),'stack',s['stack_memory_ops'],'scoreboard',s['scoreboard'],'mulstall',s['mul_stall'])

if __name__=='__main__':
    for v in ['EDAP','EDAP2']:profile(v)
    rows=[dict(variant='C_reference',cycles=5186392,retired=4589416,scoreboard=214529,branch_flush=233864,branch_request=116932,cm_per_mhz=16000000/5186392)]
    for v in ['E','EDAP','EDAP2','SP2']:
        x=json.loads((R/v/'results/metrics.json').read_text());x.pop('crc');rows.append(dict(variant=v,**x))
    output(R/'results.csv',rows)
    # SP2 must be a true scalar control; do not count data sections as instructions.
    dis=(R/'SP2/build/coremark.dis').read_text()
    assert all((int(w,16)&127)!=11 for w in re.findall(r'^\s*[0-9a-f]+:\s+([0-9a-f]{8})\s',dis,re.M))
    print('SP2 scalar encoding check PASS')
