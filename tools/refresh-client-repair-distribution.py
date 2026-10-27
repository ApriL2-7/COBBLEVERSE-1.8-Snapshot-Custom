"""Update local RC files after client-only repairs; never uploads or starts a game."""
from pathlib import Path
import json,os,hashlib,zipfile,shutil

repo=Path(__file__).resolve().parent.parent
client=Path(os.environ['APPDATA'])/'ModrinthApp/profiles/COBBLEVERSE 1.8 Integrated Test'
root=repo/'out/COBBLEVERSE-Integrated-2026.10.25-rc1'
jar=client/'mods/cobbleverse-client-callback-guard-1.0.0.jar'
pack_name='Cobbleverse-Client-Repair-2026.10.27.zip'
with zipfile.ZipFile(jar) as z:meta=json.loads(z.read('fabric.mod.json'))
manifest_path=repo/'integration/release-mod-manifest.json'
manifest=json.loads(manifest_path.read_text())
manifest=[m for m in manifest if m['id']!=meta['id']]
item={'id':meta['id'],'filename':jar.name,'version':meta['version'],'environment':'client','license':'MIT',
      'server_included':False,'client_included':True,'install_path':'mods/'+jar.name,'size':jar.stat().st_size,
      'depends':meta['depends'],'source':'locally-authored-client-hotfix'}
for algorithm in ['sha1','sha256','sha512']:item[algorithm]=hashlib.new(algorithm,jar.read_bytes()).hexdigest()
manifest.append(item)
replacements={'client-overrides/mods/'+jar.name:jar,
              'client-overrides/resourcepacks/'+pack_name:client/'resourcepacks'/pack_name,
              'overrides/config/resourcepackoverrides.json':client/'config/resourcepackoverrides.json'}
archive=root/'Player/COBBLEVERSE-Integrated-2026.10.25-rc1.mrpack';temp=archive.with_suffix('.tmp')
with zipfile.ZipFile(archive) as src,zipfile.ZipFile(temp,'w') as dst:
    for info in src.infolist():
        if info.filename in replacements:continue
        data=src.read(info.filename)
        if info.filename=='client-overrides/options.txt':
            lines=data.decode('utf8').splitlines()
            for i,line in enumerate(lines):
                if line.startswith('resourcePacks:'):
                    packs=json.loads(line.split(':',1)[1]);token='file/'+pack_name
                    packs=[p for p in packs if p!=token]+[token]
                    lines[i]='resourcePacks:'+json.dumps(packs,ensure_ascii=False,separators=(',',':'))
            data=('\n'.join(lines)+'\n').encode('utf8')
        dst.writestr(info,data)
    for name,file in replacements.items():dst.write(file,name)
with zipfile.ZipFile(temp) as z:assert z.testzip() is None
os.replace(temp,archive)
manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
status_path=repo/'integration/release-candidate-status.json'
status=json.loads(status_path.read_text());status['client_mod_count']=sum(m.get('client_included',True) for m in manifest)
status['latest_client_repairs']='2026.10.27: callback guard, Fomantis merge, resource config; gameplay unverified'
status_path.write_text(json.dumps(status,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
for side in ['Player','Server']:
    shutil.copy2(manifest_path,root/side/'mod-manifest.json')
    shutil.copy2(status_path,root/side/'KNOWN-ISSUES.json')
artifact=repo/'out/client-callback-guard'
source=repo/'client-callback-guard'
with zipfile.ZipFile(artifact/'cobbleverse-client-callback-guard-1.0.0-sources.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in source.rglob('*'):
        if p.is_file():z.write(p,'client-callback-guard/'+p.relative_to(source).as_posix())
    for name in ['build-client-callback-guard.py','test-client-callback-guard.py']:z.write(repo/'tools'/name,'tools/'+name)
shutil.copy2(artifact/'artifact.json',repo/'integration/client-callback-guard-artifact.json')
print('Local RC archive updated; client mods',status['client_mod_count'],'server mods unchanged.')
