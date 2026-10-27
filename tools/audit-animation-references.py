"""Read-only audit of enabled ZIP packs; no game launch or world access."""
from pathlib import Path
import os,json,re,zipfile,argparse
args=argparse.ArgumentParser()
args.add_argument('--include-repair',action='store_true')
args.add_argument('--profile',type=Path)
args=args.parse_args()
repo=Path(__file__).resolve().parent.parent
p=args.profile or Path(os.environ['APPDATA'])/'ModrinthApp/profiles/COBBLEVERSE 1.8 Integrated Test'
packs=json.loads(next(x.split(':',1)[1] for x in (p/'options.txt').read_text().splitlines() if x.startswith('resourcePacks:')))
sources=list((p/'mods').glob('*.jar'))+[p/'resourcepacks'/x[5:] for x in packs if x.startswith('file/') and (args.include_repair or 'Cobbleverse-Client-Repair-' not in x)]
files={}; merged={}; owners={}; bad=[]
for src in sources:
    if not src.is_file():continue
    with zipfile.ZipFile(src) as z:
        for name in z.namelist():
            if '/bedrock/pokemon/' not in name or not name.endswith('.json'):continue
            if '/animations/' not in name and '/posers/' not in name:continue
            try:data=json.loads(z.read(name))
            except (ValueError,UnicodeError):bad.append([src.name,name]);continue
            files[name]=(data,src.name)
            if '/animations/' in name:
                merged.setdefault(name,{}).update(data.get('animations',{}))
                for key in data.get('animations',{}):owners.setdefault(key,[]).append([src.name,name])
effective={};candidates={}
for name,(data,src) in files.items():
    if '/animations/' in name and name.endswith('.animation.json'):
        group=Path(name).name.removesuffix('.animation.json')
        candidates.setdefault(group,[]).append(set(data.get('animations',{})))
for group,sets in candidates.items():effective[group]=set.intersection(*sets)
union={}
for name,data in merged.items():
    group=Path(name).name.removesuffix('.animation.json')
    union.setdefault(group,set()).update(data)
pattern=re.compile(r'''bedrock(?:_stateful|_quirk|_primary_quirk)?\(\s*['"]([\w.-]+)['"]\s*,\s*['"]([\w.-]+)['"]''')
missing={}; refs=0
for name,(data,src) in files.items():
    if '/posers/' not in name:continue
    # Decode JSON first: expression quote escaping must not hide references.
    def strings(x):
        if isinstance(x,str):yield x
        elif isinstance(x,dict):
            for v in x.values():yield from strings(v)
        elif isinstance(x,list):
            for v in x:yield from strings(v)
    for s in strings(data):
        for group,anim in pattern.findall(s):
            refs+=1;key=f'animation.{group}.{anim}'
            if key not in effective.get(group,set()):
                missing.setdefault(key,{'recoverable':key in union.get(group,set()),'posers':[],'sources':owners.get(key,[])})['posers'].append([src,name])
report={'references':refs,'invalid_json':bad,'missing':missing,'recoverable_count':sum(x['recoverable'] for x in missing.values()),'unresolved_count':sum(not x['recoverable'] for x in missing.values())}
suffix='after' if args.include_repair else 'before'
(repo/f'out/integration/animation-reference-audit-{suffix}.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print(json.dumps({k:v for k,v in report.items() if k!='missing'},indent=2))
