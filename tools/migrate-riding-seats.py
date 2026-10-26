"""Migrate legacy seat data to Cobblemon 1.8 locators in local RC files.

Keeps riding behaviour/stat/spawn data. Does not launch a game or touch Oracle.
"""
from pathlib import Path
import zipfile,json,os,shutil,copy,collections,hashlib
from datetime import datetime

repo=Path(__file__).resolve().parent.parent
client=Path(os.environ['APPDATA'])/'ModrinthApp/profiles/COBBLEVERSE 1.8 Integrated Test'
root=repo/'out/COBBLEVERSE-Integrated-2026.10.25-rc1'
name='COBBLEVERSE-DP-v31.zip'
source=client/'datapacks'/name
backup=repo/'out/integration/riding-seat-backups'/datetime.now().strftime('%Y%m%d-%H%M%S')
backup.mkdir(parents=True)
options=client.joinpath('options.txt').read_text(encoding='utf8')
enabled=json.loads(next(x.split(':',1)[1] for x in options.splitlines() if x.startswith('resourcePacks:')))
packs=list((client/'mods').glob('*.jar'))+[client/'resourcepacks'/x[5:] for x in enabled if x.startswith('file/') and (client/'resourcepacks'/x[5:]).is_file()]
assets={};species={}
def canonical(s):return s if ':' in s else 'cobblemon:'+s
for file in packs:
    with zipfile.ZipFile(file) as z:
        for n in z.namelist():
            if not n.endswith('.json'):continue
            if '/bedrock/pokemon/models/' in n or '/bedrock/pokemon/resolvers/' in n:assets[n]=(file.name,z.read(n))
            elif file.suffix=='.jar' and '/species/' in n:
                try:species[n.split('/')[1]+':'+Path(n).stem]=json.loads(z.read(n))
                except (ValueError,IndexError):pass
models={};resolvers=collections.defaultdict(list)
for n,(origin,raw) in assets.items():
    try:data=json.loads(raw)
    except ValueError:continue
    if '/models/' in n:
        locators=set()
        for geometry in data.get('minecraft:geometry',[]):
            for bone in geometry.get('bones',[]):locators.update(bone.get('locators',{}))
        models[n.split('/')[1]+':'+Path(n).stem]=locators
    elif data.get('species'):
        for variation in data.get('variations',[]):
            if variation.get('model') and not variation.get('aspects'):
                resolvers[canonical(data['species'])].append(variation['model'])

replacements={};changed=[];skipped=[];warnings=[]
with zipfile.ZipFile(source) as z:
    for n in z.namelist():
        if '/species_additions/' not in n or not n.endswith('.json'):continue
        before=json.loads(z.read(n));after=copy.deepcopy(before);riding=after.get('riding',{})
        seats=riding.get('seats',[])
        if not seats or all(s.get('locator') for s in seats):continue
        target=canonical(after['target'])
        available=set().union(*(models.get(m,set()) for m in resolvers[target]))
        official=species.get(target,{}).get('riding',{}).get('seats',[])
        if official and len(official)==len(seats) and all(s.get('locator') in available for s in official):
            new_seats=copy.deepcopy(official);strategy='official-1.8.3-seat-layout'
        elif 'seat_1' in available:
            new_seats=[]
            for index,seat in enumerate(seats,1):
                locator='seat_'+str(index)
                if locator not in available:
                    # Preserve passenger slots without inventing geometry positions.
                    new_seats.append(copy.deepcopy(seat))
                    warnings.append({'species':target,'seat':index,'reason':'passenger locator missing in active base model'})
                else:
                    converted={k:v for k,v in seat.items() if k in ['condition','poseAnimations','handsBusy']}
                    converted['locator']=locator;new_seats.append(converted)
            strategy='existing-model-seat-locators'
        else:
            skipped.append({'species':target,'reason':'no verified seat_1 locator; model-specific repair required'})
            continue
        riding['seats']=new_seats
        # Everything except seat definitions must remain identical.
        old_riding=copy.deepcopy(before['riding']);new_riding=copy.deepcopy(riding)
        old_riding.pop('seats');new_riding.pop('seats');assert old_riding==new_riding
        check=copy.deepcopy(after);check['riding']['seats']=before['riding']['seats'];assert check==before
        replacements[n]=json.dumps(after,ensure_ascii=False,indent=2).encode('utf8')
        changed.append({'species':target,'path':n,'strategy':strategy,'seats':new_seats})
assert replacements, 'No legacy riding entries to migrate'
original_bytes=source.read_bytes()
assert (root/'Server/datapacks'/name).read_bytes()==original_bytes, 'Client/server data packs differ; refusing to overwrite'
for side,base in [('client',client),('server',root/'Server')]:
    target=base/'datapacks'/name
    # Both local profiles must start from the exact same data pack.
    shutil.copy2(target,backup/(side+'-'+name))
    temp=target.with_suffix('.tmp')
    # Read the original client backup for both targets; never chain transformations.
    with zipfile.ZipFile(backup/('client-'+name)) as src,zipfile.ZipFile(temp,'w') as dest:
        for info in src.infolist():dest.writestr(info,replacements.get(info.filename,src.read(info.filename)))
    with zipfile.ZipFile(temp) as check:assert check.testzip() is None
    os.replace(temp,target)
report={'migrated_species':len(changed),'changed':changed,'unresolved_primary_seats':skipped,
        'unresolved_passenger_seats':warnings,'spawn_or_riding_stats_modified':False,
        'runtime_verified':False,'oracle_applied':False,
        'sha256':hashlib.sha256(source.read_bytes()).hexdigest()}
(repo/'integration/riding-seat-migration.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print(json.dumps({k:v for k,v in report.items() if k!='changed'},ensure_ascii=False,indent=2))
