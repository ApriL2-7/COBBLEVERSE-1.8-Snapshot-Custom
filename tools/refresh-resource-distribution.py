"""Refresh the existing local player archive after verified resource repairs."""
from pathlib import Path
import os,json,zipfile,hashlib,shutil

repo=Path(__file__).resolve().parent.parent
client=Path(os.environ['APPDATA'])/'ModrinthApp/profiles/COBBLEVERSE 1.8 Integrated Test'
root=repo/'out/COBBLEVERSE-Integrated-2026.10.25-rc1'
server=root/'Server'
mega='mega_showdown-fabric-1.3.2+1.8.2+1.21.1-release.jar'
rp='Cobbleverse-Resource-Fixes-2026.10.25.zip'
archive=root/'Player/COBBLEVERSE-Integrated-2026.10.25-rc1.mrpack'
temp=archive.with_suffix('.tmp')
manifest=json.loads((repo/'integration/release-mod-manifest.json').read_text())
for item in manifest:
    if item['filename']==mega:
        p=client/'mods'/mega
        for alg in ['sha1','sha256','sha512']:item[alg]=hashlib.new(alg,p.read_bytes()).hexdigest()
        item['size']=p.stat().st_size
        item['source']='official-with-local-korean-json-repair'
        if 'version_id' in item:item['upstream_version_id']=item.pop('version_id')
        item.pop('downloads',None)
extras=[]
for p in (server/'mods').glob('disconnect-packet-fix-*.jar'):
    with zipfile.ZipFile(p) as z:meta=json.loads(z.read('fabric.mod.json'))
    item={'id':meta['id'],'version':meta['version'],'filename':p.name,'size':p.stat().st_size,
          'server_included':True,'client_included':False,'environment':'server','license':meta.get('license'),
          'depends':meta.get('depends',{}),'source':'official-exact-hash','version_id':'Gv74xveQ'}
    for alg in ['sha1','sha256','sha512']:item[alg]=hashlib.new(alg,p.read_bytes()).hexdigest()
    extras.append(item)
manifest=[m for m in manifest if m.get('client_included',True)]+extras
replacements={'overrides/mods/'+mega:client/'mods'/mega,
              'client-overrides/resourcepacks/'+rp:client/'resourcepacks'/rp,
              'overrides/config/resourcepackoverrides.json':client/'config/resourcepackoverrides.json'}
with zipfile.ZipFile(archive) as src,zipfile.ZipFile(temp,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as dest:
    for info in src.infolist():
        if info.filename in replacements:continue
        data=src.read(info.filename)
        if info.filename=='modrinth.index.json':
            index=json.loads(data);index['files']=[f for f in index['files'] if f['path']!='mods/'+mega]
            data=json.dumps(index,ensure_ascii=False,indent=2).encode('utf8')
        elif info.filename=='client-overrides/options.txt':
            lines=data.decode('utf8').splitlines()
            for i,line in enumerate(lines):
                if line.startswith('resourcePacks:'):
                    packs=json.loads(line.split(':',1)[1]);token='file/'+rp
                    packs=[p for p in packs if p!=token]+[token]
                    lines[i]='resourcePacks:'+json.dumps(packs,ensure_ascii=False,separators=(',',':'))
            data=('\n'.join(lines)+'\n').encode('utf8')
        dest.writestr(info,data)
    for name,p in replacements.items():dest.write(p,name)
with zipfile.ZipFile(temp) as z:assert z.testzip() is None
os.replace(temp,archive)
(repo/'integration/release-mod-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
(repo/'integration/server-extra-mods.json').write_text(json.dumps(extras,indent=2)+'\n',encoding='utf8')
status=json.loads((repo/'integration/release-candidate-status.json').read_text())
status.update({'server_mod_count':len(list((server/'mods').glob('*.jar'))),'server_started':True,
               'runtime_after_resource_fixes':'not yet tested','external_player_connection_before_resource_fixes':'observed in server log'})
status['known_limitations']=[s for s in status['known_limitations'] if 'Dedicated server startup' not in s and 'graphical warnings' not in s]
status['known_limitations'].append('Post-fix startup, Korean rendering, resource models, and malformed-connection workaround require runtime verification.')
if mega not in status['embedded_mods_needing_distribution_review']:
    status['embedded_mods_needing_distribution_review'].append(mega)
(repo/'integration/release-candidate-status.json').write_text(json.dumps(status,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
for folder in [root/'Player',server]:
    shutil.copy2(repo/'integration/release-mod-manifest.json',folder/'mod-manifest.json')
    shutil.copy2(repo/'integration/release-candidate-status.json',folder/'KNOWN-ISSUES.json')
print('Updated local mrpack and manifests; player mods 158, server mods',status['server_mod_count'])
