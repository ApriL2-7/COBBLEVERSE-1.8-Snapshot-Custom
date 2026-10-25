"""Build local RC artifacts only. Never publishes a release or runs a server."""
import importlib.machinery, json, pathlib, os, zipfile, shutil, hashlib, urllib.request, re
from keybind_defaults import clean_options

m=importlib.machinery.SourceFileLoader('integration',str(pathlib.Path(__file__).with_name('integrate-local.py'))).load_module()
VERSION='2026.10.25-rc1'
OUTPUT=m.REPO/'out'/('COBBLEVERSE-Integrated-'+VERSION)
SERVER=OUTPUT/'Server'
PLAYER=OUTPUT/'Player'
if OUTPUT.exists():raise RuntimeError('Output already exists; refusing overwrite: '+str(OUTPUT))
SERVER.mkdir(parents=True);PLAYER.mkdir()
shutil.copy2(m.REPO/'docs/INTEGRATED-RC.md',OUTPUT/'사용안내.md')

def metadata(p):
    with zipfile.ZipFile(p) as z:return json.loads(z.read('fabric.mod.json'),strict=False)

mods={}
for p in sorted((m.TARGET/'mods').glob('*.jar')):
    info=metadata(p)
    if info['id'] in mods:raise RuntimeError('Duplicate active Mod ID: '+info['id'])
    mods[info['id']]={'path':p,'meta':info}
assert mods['cobblemon']['meta']['version']=='1.8.3+1.21.1'

# Use the existing server as a read-only classification reference; use only
# the CURRENT client binaries in the new server bundle.
reference_ids=set()
for p in (m.REPO.parent/'mods').glob('*.jar'):
    try:reference_ids.add(metadata(p)['id'])
    except (KeyError,ValueError,zipfile.BadZipFile):pass
server_ids=(reference_ids|{'ftblibrary','ftbteams','ftbquests','cobblemon_quests','pcenhancements','cobblemon_battle_tower','wild_battle_api'})&mods.keys()
server_ids={i for i in server_ids if mods[i]['meta'].get('environment','*')!='client'}
changed=True
while changed:
    changed=False
    for i in list(server_ids):
        for dep in mods[i]['meta'].get('depends',{}):
            if dep in mods and dep not in server_ids:
                if mods[dep]['meta'].get('environment','*')=='client':raise RuntimeError('Server dependency is client-only: '+dep)
                server_ids.add(dep);changed=True

# Public download metadata is taken from official pack/version metadata already
# retrieved. No local hashes or installation metadata are sent to any service.
official={}
with zipfile.ZipFile(m.LOCAL/'downloads/COBBLEVERSE 1.7.42.mrpack') as z:
    index=json.loads(z.read('modrinth.index.json'))
    for f in index['files']:official[f['hashes']['sha1']]=f
for p in (m.OUT/'official').glob('*.json'):
    data=json.loads(p.read_text(encoding='utf8'))
    if not isinstance(data,list):continue
    for v in data:
        for f in v.get('files',[]):
            if f.get('hashes',{}).get('sha1'):
                official[f['hashes']['sha1']]={'downloads':[f['url']],'project_id':v['project_id'],'version_id':v['id']}

def acceptable(p,base):
    rel=p.relative_to(base)
    if any(x.lower() in {'libraries','cache','caches','logs','debug','crash-reports','snapshots','skins'} for x in rel.parts):return False
    if any(x.startswith('.') for x in rel.parts):return False
    if any(x in str(rel).lower() for x in ['integration-verification-only','nvsdk_ngx','downloadcache']):return False
    return p.suffix.lower() not in {'.log','.lock','.bak','.disabled','.dll','.exe','.class'}

shared=[];client=[]
for folder in ['config','datapacks','defaultconfigs']:
    base=m.TARGET/folder
    if not base.exists():continue
    for p in sorted(base.rglob('*')):
        if p.is_file() and acceptable(p,base):shared.append((p,p.relative_to(m.TARGET).as_posix()))
for folder in ['resourcepacks','shaderpacks','fancymenu_data','licenses']:
    base=m.TARGET/folder
    if not base.exists():continue
    for p in sorted(base.rglob('*')):
        if p.is_file() and acceptable(p,base):client.append((p,p.relative_to(m.TARGET).as_posix()))

manifest=[];files=[];embedded=[]
with zipfile.ZipFile(PLAYER/('COBBLEVERSE-Integrated-'+VERSION+'.mrpack'),'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as pack:
    for ident,entry in mods.items():
        p=entry['path'];meta=entry['meta'];sha1=m.digest(p,'sha1');sha512=m.digest(p,'sha512');sha256=m.digest(p)
        remote=official.get(sha1);is_server=ident in server_ids
        item={'id':ident,'version':meta['version'],'filename':p.name,'sha256':sha256,'sha1':sha1,'sha512':sha512,'size':p.stat().st_size,'install_path':'mods/'+p.name,'environment':meta.get('environment','*'),'server_included':is_server,'license':meta.get('license'),'depends':meta.get('depends',{}),'entrypoints':meta.get('entrypoints',{}),'source':'local-custom-or-unresolved'}
        if remote:
            files.append({'path':'mods/'+p.name,'hashes':{'sha1':sha1,'sha512':sha512},'downloads':remote['downloads'],'fileSize':p.stat().st_size,'env':{'client':'required','server':'required' if is_server else 'unsupported'}})
            item.update({k:remote[k] for k in ['project_id','version_id'] if k in remote});item['downloads']=remote['downloads'];item['source']='official-exact-hash'
        else:
            pack.write(p,('overrides/' if is_server else 'client-overrides/')+'mods/'+p.name);embedded.append(p.name)
        manifest.append(item)
        if is_server:
            dest=SERVER/'mods'/p.name;dest.parent.mkdir(exist_ok=True);shutil.copy2(p,dest)
    for p,rel in shared:
        pack.write(p,'overrides/'+rel)
        dest=SERVER/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
    for p,rel in client:pack.write(p,'client-overrides/'+rel)
    options=(m.TARGET/'options.txt').read_text(encoding='utf8')
    options=clean_options(options)[0]
    pack.writestr('client-overrides/options.txt',options)
    pack.writestr('modrinth.index.json',json.dumps({'formatVersion':1,'game':'minecraft','versionId':VERSION,'name':'COBBLEVERSE Integrated RC','summary':'Local release candidate: Cobblemon 1.8.3, FTB Questbook, Battle Tower, PC Enhancements. Not fully validated.','files':files,'dependencies':{'minecraft':'1.21.1','fabric-loader':'0.18.4'}},ensure_ascii=False,indent=2))

# Explicit server-only fixes are kept out of the player profile/archive.
extra_file=m.OUT/'server-extra-mods.json'
extra_mods=json.loads(extra_file.read_text(encoding='utf8')) if extra_file.exists() else []
for extra in extra_mods:
    remote=official[extra['sha1']]
    destination=SERVER/'mods'/extra['filename']
    urllib.request.urlretrieve(remote['downloads'][0],destination)
    if m.digest(destination)!=extra['sha256']:raise RuntimeError('Server-only download hash mismatch')
    manifest.append(extra)

with urllib.request.urlopen('https://meta.fabricmc.net/v2/versions/installer',timeout=60) as r:installers=json.load(r)
installer=next(v for v in installers if v.get('stable'))['version']
url=f'https://meta.fabricmc.net/v2/versions/loader/1.21.1/0.18.4/{installer}/server/jar'
launcher=SERVER/'fabric-server-launch.jar'
urllib.request.urlretrieve(url,launcher)
with zipfile.ZipFile(launcher) as z:
    if 'META-INF/MANIFEST.MF' not in z.namelist():raise RuntimeError('Invalid Fabric launcher')
m.dump(m.OUT/'server-launcher-provenance.json',{'minecraft':'1.21.1','fabric_loader':'0.18.4','installer':installer,'url':url,'sha256':m.digest(launcher)})

(SERVER/'eula.txt').write_text('# Read https://aka.ms/MinecraftEULA before changing this value.\neula=false\n',encoding='utf8')
(SERVER/'server.properties').write_text('''# Fresh integrated RC server; no existing world or player data included.
level-name=world
server-port=25565
server-ip=
online-mode=true
max-players=10
allow-flight=true
enable-command-block=true
function-permission-level=2
difficulty=normal
view-distance=8
simulation-distance=6
motd=Cobbleverse Integrated 1.8.3 RC
enable-rcon=false
''',encoding='utf8')
(SERVER/'start-server.bat').write_text('''@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
java -version
if errorlevel 1 (
  echo Install Java 21 and add java.exe to PATH.
  pause
  exit /b 1
)
java -Xms2G -Xmx8G -Dfile.encoding=UTF-8 -jar fabric-server-launch.jar nogui
pause
''',encoding='ascii')
(SERVER/'start-server.sh').write_text('#!/usr/bin/env sh\nset -eu\ncd "$(dirname "$0")"\nexec java -Xms2G -Xmx8G -Dfile.encoding=UTF-8 -jar fabric-server-launch.jar nogui\n',encoding='utf8')

known={'status':'release-candidate-not-fully-validated','minecraft':'1.21.1','fabric_loader':'0.18.4','cobblemon':'1.8.3+1.21.1','cobblemon_commit':'ffe005511dd0d3ba68377fa3f95906b3837d9a0e','client_mod_count':len(mods),'server_mod_count':len(server_ids),'server_started':False,'known_limitations':['Dedicated server startup and external-player connection have not been tested.','Battle Tower initialized, team locked, and NPC battle started; win/streak/reward cycle not completed.','PC Enhancements loaded; actual global sorting and lock persistence not tested.','Questbook loaded 41 chapters and 1366 quests; full completion/reward coverage not tested.','Questbook references unavailable lumymon:zeraorite and lumymon:zygardite.','Quest Pokedex handler can log owner-null warnings for trainer Pokemon; no fatal crash seen for that warning.','Client graphical warnings for some existing model references remain.','Redistribution permission review is required before publishing embedded third-party or modified binaries.'],'excluded':['worlds','player data','account credentials','logs','disabled JARs','verification-only datapack','native-library cache'],'github_deployment':{'repository':'ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom','existing_updater_supports':['mods/','resourcepacks/'],'recommended':'Publish the full mrpack as a separate RC release asset; do not feed it to the legacy incremental updater.','published':False},'embedded_mods_needing_distribution_review':embedded}
known['server_mod_count']=len(server_ids)+len(extra_mods)
m.dump(m.OUT/'release-candidate-status.json',known)
m.dump(m.OUT/'release-mod-manifest.json',manifest)
for folder in [PLAYER,SERVER]:
    shutil.copy2(m.OUT/'release-mod-manifest.json',folder/'mod-manifest.json')
    shutil.copy2(m.OUT/'release-candidate-status.json',folder/'KNOWN-ISSUES.json')
print('OUTPUT',OUTPUT,flush=True)
print('Client mods',len(mods),'server mods',len(server_ids)+len(extra_mods),'official download entries',len(files),'embedded',len(embedded),flush=True)
print('SERVER FOLDER READY; server was not executed',flush=True)
