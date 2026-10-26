"""Apply the official 1.3.6 client crash fix to the stopped local profile and RC.

Never connects to or restarts the operational Oracle server.
"""
from pathlib import Path
import json,zipfile,hashlib,shutil,os

repo=Path(__file__).resolve().parent.parent
client=Path(os.environ['APPDATA'])/'ModrinthApp/profiles/COBBLEVERSE 1.8 Integrated Test'
root=repo/'out/COBBLEVERSE-Integrated-2026.10.25-rc1'
version=json.loads((repo/'integration/official/more-cobblemon-tweaks.json').read_text())[0]
file=next(f for f in version['files'] if f['primary'])
new=repo/'out/integration/downloads'/file['filename']
assert hashlib.sha512(new.read_bytes()).hexdigest()==file['hashes']['sha512']
old='MoreCobblemonTweaks-fabric-1.3.3.jar'
backup=repo/'out/integration/more-tweaks-1.3.3-backup'
for side,base in [('client',client),('server',root/'Server')]:
    source=base/'mods'/old
    dest=backup/side/old
    if source.exists():
        dest.parent.mkdir(parents=True,exist_ok=True)
        if dest.exists():assert dest.read_bytes()==source.read_bytes()
        else:shutil.copy2(source,dest)
        source.unlink()
    shutil.copy2(new,base/'mods'/new.name)
manifest_path=repo/'integration/release-mod-manifest.json'
manifest=json.loads(manifest_path.read_text())
with zipfile.ZipFile(new) as z:meta=json.loads(z.read('fabric.mod.json'))
for item in manifest:
    if item['id']!='more_cobblemon_tweaks':continue
    item.update({'filename':new.name,'version':meta['version'],'size':new.stat().st_size,
                 'install_path':'mods/'+new.name,'depends':meta['depends'],'source':'official-exact-hash',
                 'project_id':version['project_id'],'version_id':version['id'],'downloads':[file['url']]})
    for alg in ['sha1','sha256','sha512']:item[alg]=hashlib.new(alg,new.read_bytes()).hexdigest()
manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
pack=root/'Player/COBBLEVERSE-Integrated-2026.10.25-rc1.mrpack'
temp=pack.with_suffix('.tmp')
with zipfile.ZipFile(pack) as src,zipfile.ZipFile(temp,'w') as dst:
    for info in src.infolist():
        if info.filename.endswith('/mods/'+old):continue
        data=src.read(info.filename)
        if info.filename=='modrinth.index.json':
            index=json.loads(data)
            index['files']=[f for f in index['files'] if f['path'] not in ['mods/'+old,'mods/'+new.name]]
            index['files'].append({'path':'mods/'+new.name,'hashes':file['hashes'],'downloads':[file['url']],
                                   'fileSize':new.stat().st_size,'env':{'client':'required','server':'required'}})
            data=json.dumps(index,ensure_ascii=False,indent=2).encode('utf8')
        dst.writestr(info,data)
with zipfile.ZipFile(temp) as z:assert z.testzip() is None
os.replace(temp,pack)
for side in ['Server','Player']:shutil.copy2(manifest_path,root/side/'mod-manifest.json')
standalone=repo/'out'/new.name
shutil.copy2(new,standalone)
print('Updated stopped local client, local RC server and player archive to official 1.3.6.')
print('Oracle was not modified or restarted. Player-only crash fix requires client update.')
print('Player replacement file:',standalone)
