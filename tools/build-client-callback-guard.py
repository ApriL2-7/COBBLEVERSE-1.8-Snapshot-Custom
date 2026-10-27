"""Build a client-only MIT hotfix using installed dependencies; do not run Minecraft."""
from pathlib import Path
import os,subprocess,zipfile,hashlib,json,shutil

repo=Path(__file__).resolve().parent.parent
profile=Path(os.environ['APPDATA'])/'ModrinthApp/profiles/COBBLEVERSE 1.8 Integrated Test'
meta=Path(os.environ['APPDATA'])/'ModrinthApp/meta'
out=repo/'out/client-callback-guard';out.mkdir(exist_ok=True)
classes=out/'classes';classes.mkdir(exist_ok=True)
core=profile/'mods/Cobblemon-fabric-1.8.3+1.21.1.jar'
mixins=next((meta/'libraries/net/fabricmc/sponge-mixin/0.17.0+mixin.0.8.7').glob('*.jar'))
game=meta/'versions/1.21.1-0.18.4/1.21.1-0.18.4.jar'
with zipfile.ZipFile(next((profile/'mods').glob('fabric-language-kotlin-*.jar'))) as z:
    entry=next(n for n in z.namelist() if n.startswith('META-INF/jars/kotlin-stdlib-') and '-jdk' not in n)
    stdlib=out/'kotlin-stdlib.jar';stdlib.write_bytes(z.read(entry))
javac=Path(os.environ.get('JAVA_HOME',r'C:\Program Files\Java\jdk-21.0.12'))/'bin/javac.exe'
source=repo/'client-callback-guard'
subprocess.run([str(javac),'--release','21','-proc:none','-classpath',os.pathsep.join(map(str,[core,mixins,stdlib,game])),
                '-d',str(classes),*map(str,(source/'src').rglob('*.java'))],check=True)
jar=out/'cobbleverse-client-callback-guard-1.0.0.jar'
with zipfile.ZipFile(jar,'w',zipfile.ZIP_DEFLATED) as z:
    for p in classes.rglob('*.class'):z.write(p,p.relative_to(classes).as_posix())
    for name in ['fabric.mod.json','cobbleverse_client_callback_guard.mixins.json','LICENSE']:z.write(source/name,name)
sources=out/'cobbleverse-client-callback-guard-1.0.0-sources.zip'
with zipfile.ZipFile(sources,'w',zipfile.ZIP_DEFLATED) as z:
    for p in source.rglob('*'):
        if p.is_file():z.write(p,'client-callback-guard/'+p.relative_to(source).as_posix())
    z.write(Path(__file__),'tools/'+Path(__file__).name)
report={'file':jar.name,'sha256':hashlib.sha256(jar.read_bytes()).hexdigest(),'bytes':jar.stat().st_size,
        'client_only':True,'requires_cobblemon':'1.8.3+1.21.1','runtime_tested':False}
(out/'artifact.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
print(json.dumps(report,indent=2))
