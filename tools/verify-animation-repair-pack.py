"""Check generated packs against every original definition, without a game launch."""
from pathlib import Path
import argparse,json,zipfile,collections
repo=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser();parser.add_argument('profile',type=Path);a=parser.parse_args();p=a.profile
pack_name='Cobbleverse-Client-Repair-2026.10.27.zip'
mods=[]
for path in (p/'mods').glob('*.jar'):
    with zipfile.ZipFile(path) as z:meta=json.loads(z.read('fabric.mod.json'),strict=False)
    mods.append((meta['id'],path))
packs=json.loads(next(x.split(':',1)[1] for x in (p/'options.txt').read_text().splitlines() if x.startswith('resourcePacks:')))
sources=[path for _,path in sorted(mods)]+[p/'resourcepacks'/x[5:] for x in packs if x.startswith('file/') and x!='file/'+pack_name]
files={};groups=collections.defaultdict(dict)
for src in sources:
    if not src.is_file():continue
    with zipfile.ZipFile(src) as z:
        for name in z.namelist():
            if '/bedrock/pokemon/animations/' not in name or not name.endswith('.animation.json'):continue
            data=json.loads(z.read(name));animations=data.get('animations',{})
            if not animations:continue
            file=files.setdefault(name,{'data':None,'union':{}})
            file['data']=data;file['union'].update(animations)
            groups[Path(name).name].update(animations)
expected={};restored=0
for name,file in files.items():
    union=groups[Path(name).name]|file['union']
    missing=union.keys()-file['data']['animations'].keys()
    if not missing:continue
    restored+=len(missing)
    expected[name]=file['data']|{'animations':union}
with zipfile.ZipFile(p/'resourcepacks'/pack_name) as z:
    assert z.testzip() is None
    assert set(z.namelist())==set(expected)|{'pack.mcmeta'}
    for name,data in expected.items():assert json.loads(z.read(name))==data,name
    vileplume=[name for name in expected if name.endswith('/vileplume.animation.json')]
    for name in vileplume:assert 'animation.vileplume.quirk' in expected[name]['animations']
report={'repair_files':len(expected),'restored_names_across_files':restored,
        'all_original_values_and_metadata_preserved':True,'zip_crc':'passed',
        'vileplume_quirk_verified':bool(vileplume),'minecraft_started':False}
print(json.dumps(report,indent=2))
if 'friend-animation-profile' in str(p):
    before=json.loads((repo/'out/integration/animation-reference-audit-before.json').read_text())
    after=json.loads((repo/'out/integration/animation-reference-audit-after.json').read_text())
    report['static_reference_audit']={'references':after['references'],'recoverable_before':before['recoverable_count'],
      'recoverable_after':after['recoverable_count'],'unresolved_original_references':after['unresolved_count'],
      'invalid_original_json_count':len(after['invalid_json']),
      'limitations':'Literal bedrock references only; directory and built-in variant packs are not audited; no gameplay test.'}
    (repo/'integration/animation-repair-verification.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
