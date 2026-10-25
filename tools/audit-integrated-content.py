"""Record content provenance and terrain/structure compatibility without player data."""
import importlib.machinery,json,zipfile,re,urllib.request,collections,urllib.parse
from pathlib import Path

m=importlib.machinery.SourceFileLoader('integration',str(Path(__file__).with_name('integrate-local.py'))).load_module()
mods=[m.mod(p) for p in sorted((m.TARGET/'mods').glob('*.jar'))]
ids=collections.Counter(x.get('id') for x in mods)
assert all(n==1 for n in ids.values()),ids
# Use ONLY version IDs explicitly published as dependencies of the official
# public Cobbleverse release. Never read the user's Modrinth database here.
public_pack=json.loads((m.OUT/'official/cobbleverse.json').read_text(encoding='utf8'))[0]
version_ids={d['version_id'] for d in public_pack['dependencies'] if d.get('version_id')}
versions=[]
for p in (m.OUT/'official').glob('*.json'):
    data=json.loads(p.read_text(encoding='utf8'))
    if isinstance(data,list):versions.extend(data)
version_ids.update(v['id'] for v in versions)
ids=sorted(version_ids)
for offset in range(0,len(ids),50):
    route='versions?ids='+urllib.parse.quote(json.dumps(ids[offset:offset+50]))
    versions.extend(m.api(route))
official={f['hashes']['sha1']:v for v in versions for f in v.get('files',[]) if 'sha1' in f.get('hashes',{})}
for x in mods:
    version=official.get(x['sha1'])
    x['install_path']='mods/'+x['filename']
    x['classification']='client' if x.get('environment')=='client' else 'common'
    x['provenance']='local-custom-or-unresolved'
    if version:
        x['project_id']=version['project_id'];x['version_id']=version['id']
        x['official_downloads']=[f['url'] for f in version['files'] if f['hashes'].get('sha1')==x['sha1']]
        x['provenance']='official-hash-match'
m.dump(m.OUT/'final-mod-manifest.json',mods)
rules=[]
for line in (m.TARGET/'config/biome_replacer.properties').read_text(encoding='utf8').splitlines():
    if '>' in line and not line.lstrip().startswith(('!','#')):rules.append([x.strip() for x in line.split('>',1)])
structures={};datapacks=[]
for p in sorted((m.TARGET/'datapacks').rglob('*.zip')):
    with zipfile.ZipFile(p) as z:
        names=z.namelist();pack=json.loads(z.read('pack.mcmeta'))
        datapacks.append({'path':p.relative_to(m.TARGET).as_posix(),'sha256':m.digest(p),'pack':pack,'activation':'optional-region' if 'extra' in p.parts else 'required'})
        for n in names:
            if '/worldgen/structure/' in n and n.endswith('.json'):
                try:
                    obj=json.loads(z.read(n));biomes=obj.get('biomes',[])
                    if isinstance(biomes,str):biomes=[biomes]
                    structures[p.name+':'+n]=biomes
                except (ValueError,KeyError):pass
required={b for bs in structures.values() for b in bs if b.startswith('terralith:')}
replaced={r[0] for r in rules}
m.dump(m.OUT/'terrain-audit.json',{'replacement_rule_count':len(rules),'rules':rules,'required_terralith_biomes':sorted(required),'replaced_structure_biomes':sorted(required&replaced),'structures':structures,'note':'No biome replacement rule or spawn-rate value changed. Optional regional packs remain progression-controlled.'})
m.dump(m.OUT/'datapack-manifest.json',datapacks)
resources=[{'path':p.relative_to(m.TARGET).as_posix(),'sha256':m.digest(p),'size':p.stat().st_size} for p in sorted((m.TARGET/'resourcepacks').glob('*.zip'))]
m.dump(m.OUT/'resourcepack-manifest.json',resources)
# Compare the latest official pack without installing it over the custom profile.
v=json.loads((m.OUT/'official/cobbleverse.json').read_text(encoding='utf8'))[0]
archive=m.download_version(v)
with zipfile.ZipFile(archive) as z:
    index=json.loads(z.read('modrinth.index.json'))
    m.dump(m.OUT/'official-pack-comparison.json',{'version_id':v['id'],'version':v['version_number'],'dependencies':index['dependencies'],'official_files':len(index['files']),'local_mods':len(mods),'matched_official_mods':sum(x['provenance']=='official-hash-match' for x in mods),'override_changes':[{'path':n,'same_as_local':(m.TARGET/n.removeprefix('overrides/')).exists() and m.digest(m.TARGET/n.removeprefix('overrides/'))==__import__('hashlib').sha256(z.read(n)).hexdigest()} for n in z.namelist() if n.startswith('overrides/') and not n.endswith('/') and (n.endswith('.zip') or n.endswith('global_packs.toml'))]})
print('Mods',len(mods),'official exact hash matches',len(official),'biome rules',len(rules),'structure conflicts',sorted(required&replaced),flush=True)
