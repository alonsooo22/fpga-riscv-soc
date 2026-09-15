from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parent
for manifest in sorted(r.glob('2026-09-16/*/manifest.json')):
    data=json.loads(manifest.read_text(encoding='utf-8'))
    for entry in data['files']:
        p=manifest.parent/entry['file']
        assert p.is_file(),p
        assert hashlib.sha256(p.read_bytes()).hexdigest()==entry['sha256'],p
    print('PASS',manifest.parent.name,len(data['files']),'files')
for x in json.loads((r/'common/manifest.json').read_text(encoding='utf-8')):
    p=r/'common'/x['file'];assert hashlib.sha256(p.read_bytes()).hexdigest()==x['sha256'],p
print('PASS shared runtime sources')
