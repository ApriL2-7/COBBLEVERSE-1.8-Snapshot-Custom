"""Repair observed resource errors in the stopped integrated client/server.

Backups stay in ignored out/. The source profile and world data are never edited.
"""
from pathlib import Path
import os, json, zipfile, hashlib, shutil, re, urllib.request
from datetime import datetime

REPO = Path(__file__).resolve().parent.parent
CLIENT = Path(os.environ['APPDATA'])/'ModrinthApp/profiles/COBBLEVERSE 1.8 Integrated Test'
ROOT = REPO/'out/COBBLEVERSE-Integrated-2026.10.25-rc1'
SERVER = ROOT/'Server'
BACKUP = REPO/'out/integration/runtime-fix-backups'/datetime.now().strftime('%Y%m%d-%H%M%S')
BACKUP.mkdir(parents=True)
report = {'changes': [], 'runtime_verified': False}

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def backup(p, side):
    dest = BACKUP/side/p.relative_to(CLIENT if side=='client' else SERVER)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(p, dest)

mega = 'mega_showdown-fabric-1.3.2+1.8.2+1.21.1-release.jar'
entry = 'assets/cobblemon/lang/ko_kr.json'
with zipfile.ZipFile(CLIENT/'mods'/mega) as z:
    text = z.read(entry).decode('utf8')
try:
    json.loads(text)
    fixed = text
except json.JSONDecodeError:
    fixed, count = re.subn(r'("cobblemon\.move\.dragoncheer\.desc"\s*:\s*"[^"\n]*")\s*("cobblemon\.ui\.pokedex\.info\.form\.pikachu-cosplay")', r'\1,\n  \2', text)
    assert count == 1, 'Unexpected Korean translation contents; refusing broad repair'
    json.loads(fixed)
for side, base in [('client', CLIENT), ('server', SERVER)]:
    jar = base/'mods'/mega
    with zipfile.ZipFile(jar) as z:
        old = z.read(entry)
    if old == fixed.encode('utf8'): continue
    backup(jar, side)
    temp = jar.with_suffix('.tmp')
    with zipfile.ZipFile(jar) as src, zipfile.ZipFile(temp, 'w') as dst:
        for info in src.infolist():
            dst.writestr(info, fixed.encode('utf8') if info.filename==entry else src.read(info.filename))
    with zipfile.ZipFile(temp) as z:
        assert z.testzip() is None
        json.loads(z.read(entry))
    os.replace(temp, jar)
    report['changes'].append({'side': side, 'file': 'mods/'+mega, 'fix': 'missing comma in Korean language JSON', 'sha256': sha(jar)})

# Fix resource references using the original geometry/textures where present.
resources = {}
def put(name, value): resources[name] = json.dumps(value, ensure_ascii=False, indent=2).encode('utf8')
def read_mod(prefix, entry):
    jar = next((CLIENT/'mods').glob(prefix+'*.jar'))
    with zipfile.ZipFile(jar) as z: return z.read(entry)
model = json.loads(read_mod('cobblenav-', 'assets/cobblenav/models/item/track_arrow.json'))
model.pop('parent', None)  # Self-contained Blockbench geometry referenced a nonexistent parent.
put('assets/cobblenav/models/item/track_arrow.json', model)
for kind in ['pokemon_spawner', 'pokemon_trial_spawner']:
    resources[f'assets/cobblemon-additions/blockstates/{kind}.json'] = read_mod('cobblemon-additions-', f'assets/bca/blockstates/{kind}.json')
    resources[f'assets/cobblemon-additions/models/item/{kind}.json'] = read_mod('cobblemon-additions-', f'assets/bca/models/item/{kind}.json')
put('assets/legendarymonuments/models/block/pokemon_trial_spawner_ominous.json', {'parent':'minecraft:block/trial_spawner_inactive_ominous'})
resources['assets/cozyhome/textures/block/inset_water_still.png'] = read_mod('Luckys-Cozyhome-', 'assets/cozyhome/textures/block/liquid/inset_water_still.png')
resources['assets/pokeblocks/textures/block/pokedoll_shiny_cubchoo_animated_texture.png'] = read_mod('pokeblocks-', 'assets/pokeblocks/textures/block/pokedoll_cubchoo_animated_shiny_texture.png')
# Internal liquid block has no item model. Use a vanilla water icon for its inventory form.
put('assets/cozyhome/models/item/falling_liquid.json', {'parent':'minecraft:item/generated', 'textures':{'layer0':'minecraft:item/water_bucket'}})
put('pack.mcmeta', {'pack':{'pack_format':34,'description':'Cobbleverse resource reference fixes 2026.10.25'}})
pack_name = 'Cobbleverse-Resource-Fixes-2026.10.25.zip'
pack = CLIENT/'resourcepacks'/pack_name
if pack.exists(): backup(pack, 'client')
with zipfile.ZipFile(pack, 'w', zipfile.ZIP_DEFLATED) as z:
    for name, data in resources.items(): z.writestr(name, data)

config = CLIENT/'config/resourcepackoverrides.json'
data = json.loads(config.read_text(encoding='utf8'))
component_fixes = 0
for fields in list(data.get('pack_overrides', {}).values())+[data.get('default_overrides', {})]:
    for field in ['title','description']:
        value = fields.get(field)
        if not isinstance(value,str): continue
        try: json.loads(value)
        except json.JSONDecodeError:
            try: decoded = json.loads(value, strict=False)
            except json.JSONDecodeError: decoded = value
            fields[field] = json.dumps(decoded, ensure_ascii=False)
            component_fixes += 1
    for field in ['title','description']:
        if isinstance(fields.get(field),str): json.loads(fields[field])
for name in ['!Cobbleverse Questsbook Resourcepack.zip', pack_name]:
    token = 'file/'+name
    if (CLIENT/'resourcepacks'/name).exists() and token not in data['default_packs']:
        data['default_packs'].append(token)
backup(config, 'client')
config.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
options = CLIENT/'options.txt'
original = options.read_text(encoding='utf8')
lines = original.splitlines()
for i,line in enumerate(lines):
    if line.startswith('resourcePacks:'):
        packs = json.loads(line.split(':',1)[1]);token='file/'+pack_name
        packs = [p for p in packs if p!=token]+[token]
        lines[i] = 'resourcePacks:'+json.dumps(packs,ensure_ascii=False,separators=(',',':'))
        break
else: raise RuntimeError('resourcePacks setting absent')
backup(options,'client');options.write_text('\n'.join(lines)+'\n',encoding='utf8')
report['changes'].append({'side':'client','file':'config/resourcepackoverrides.json','nested_text_components_repaired':component_fixes})
report['changes'].append({'side':'client','file':'resourcepacks/'+pack_name,'resource_count':len(resources),'sha256':sha(pack)})

# Official, MIT-licensed server-only workaround for the exact logged MC-271325 error.
url='https://api.modrinth.com/v2/version/Gv74xveQ'
with urllib.request.urlopen(url,timeout=30) as r: version=json.load(r)
assert 'fabric' in version['loaders'] and '1.21.1' in version['game_versions']
file=next(f for f in version['files'] if f['primary'])
with urllib.request.urlopen(file['url'],timeout=30) as r: payload=r.read()
assert hashlib.sha512(payload).hexdigest()==file['hashes']['sha512']
dest=SERVER/'mods'/file['filename']
if dest.exists(): backup(dest,'server')
dest.write_bytes(payload)
with zipfile.ZipFile(dest) as z:
    meta=json.loads(z.read('fabric.mod.json'))
    assert meta['id']=='disconnect-packet-fix' and meta['environment']=='server'
report['changes'].append({'side':'server','file':'mods/'+file['filename'],'fix':'MC-271325 workaround','version_id':version['id'],'url':file['url'],'sha512':file['hashes']['sha512']})
(REPO/'integration/official/disconnect-packet-fix.json').write_text(json.dumps([version],indent=2)+'\n',encoding='utf8')
(REPO/'integration/runtime-resource-fixes.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print(json.dumps(report,ensure_ascii=False,indent=2))
