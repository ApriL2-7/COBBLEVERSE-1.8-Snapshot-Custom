"""Launch only the isolated client with a synthetic offline test identity.

Uses installed Modrinth game assets and Java. Never reads account credentials.
"""
import pathlib,os,json,subprocess,uuid,sys
from importlib.machinery import SourceFileLoader

base=pathlib.Path(__file__).resolve().parents[1]
if '--approved' not in sys.argv:
    raise RuntimeError('User approval required before the next interactive test. Relaunch with --approved only after explicit permission.')
integration=SourceFileLoader('integration',str(base/'tools/integrate-local.py')).load_module()
meta=pathlib.Path(os.environ['APPDATA'])/'ModrinthApp/meta'
target=integration.TARGET
if not target.is_dir():raise RuntimeError('Prepare isolated profile first')
mods=[integration.mod(p) for p in (target/'mods').glob('*.jar')]
ids=[m.get('id') for m in mods]
duplicates=sorted({i for i in ids if ids.count(i)>1})
if duplicates:raise RuntimeError('Duplicate active mod IDs: '+str(duplicates))
version='1.21.1-0.18.4'
v=json.loads((meta/'versions'/version/(version+'.json')).read_text())
classpath=[]
for lib in v['libraries']:
    allowed=not lib.get('rules')
    for rule in lib.get('rules',[]):
        if rule.get('os',{}).get('name','windows')=='windows':allowed=rule['action']=='allow'
    if not allowed or not lib.get('include_in_classpath',True):continue
    artifact=lib.get('downloads',{}).get('artifact',{}).get('path')
    if not artifact:
        group,artifactid,ver=lib['name'].split(':')[:3]
        artifact=f'{group.replace(".","/")}/{artifactid}/{ver}/{artifactid}-{ver}.jar'
    p=meta/'libraries'/artifact
    if not p.exists():raise FileNotFoundError(p)
    classpath.append(str(p))
classpath.append(str(meta/'versions'/version/(version+'.jar')))
java=next((meta/'java_versions').glob('*/bin/java.exe'))
natives=meta/'natives'/version
command=[str(java),'-Xms1G','-Xmx6G','-Dfile.encoding=UTF-8',f'-Djava.library.path={natives}',f'-Djna.tmpdir={natives}',f'-Dorg.lwjgl.system.SharedLibraryExtractPath={natives}',f'-Dio.netty.native.workdir={natives}','-Dminecraft.launcher.brand=integration-test','-Dminecraft.launcher.version=1','-cp',';'.join(classpath),v['mainClass'],'--username','IntegrationTest','--version',version,'--gameDir',str(target),'--assetsDir',str(meta/'assets'),'--assetIndex',v['assets'],'--uuid',uuid.uuid3(uuid.NAMESPACE_DNS,'cobbleverse-integration-test').hex,'--accessToken','0','--userType','legacy','--versionType','release','--width','1280','--height','720']
logs=base/'out/integration'
logs.mkdir(parents=True,exist_ok=True)
with (logs/'client-console-private.log').open('wb') as output:
    process=subprocess.Popen(command,cwd=target,stdout=output,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
(logs/'client-process.json').write_text(json.dumps({'pid':process.pid,'profile':str(target),'identity':'synthetic-offline','version':version}))
print('Started isolated client PID',process.pid)
