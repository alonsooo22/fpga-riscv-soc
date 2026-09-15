"""Restore source layout into a NEW directory; never overwrite development trees."""
from pathlib import Path
import sys,shutil
root=Path(__file__).resolve().parent
if len(sys.argv)!=3:raise SystemExit('usage: materialize.py ultra-v4-c|ultra-v4-simd-edap2 NEW_OUTPUT_DIRECTORY')
assert sys.argv[1] in ['ultra-v4-c','ultra-v4-simd-edap2']
s=root/'2026-09-16'/sys.argv[1];out=Path(sys.argv[2]).resolve()
if out.exists():raise SystemExit('Refusing to overwrite an existing directory')
shutil.copytree(s/'rtl',out)
shutil.copytree(s/'simulation/tb',out/'top_tcm_axi/tb')
shutil.copytree(root/'common/isa_sim',out/'isa_sim')
shutil.copytree(s/'software',out/'benchmarks/coremark-ultra')
shutil.copy2(s/'config.json',out/'archive_config.json')
print('Sources restored:',out,'; no builds or simulations were run.')
