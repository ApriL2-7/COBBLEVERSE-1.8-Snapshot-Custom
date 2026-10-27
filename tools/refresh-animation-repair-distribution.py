"""Replace only the generated animation repair in the existing local RC archive."""
from pathlib import Path
import os,zipfile,json
repo=Path(__file__).resolve().parent.parent
client=Path(os.environ['APPDATA'])/'ModrinthApp/profiles/COBBLEVERSE 1.8 Integrated Test'
name='Cobbleverse-Client-Repair-2026.10.27.zip'
archive=repo/'out/COBBLEVERSE-Integrated-2026.10.25-rc1/Player/COBBLEVERSE-Integrated-2026.10.25-rc1.mrpack'
entry='client-overrides/resourcepacks/'+name
temp=archive.with_suffix('.animation-repair.tmp')
with zipfile.ZipFile(archive) as src,zipfile.ZipFile(temp,'w') as dst:
    for info in src.infolist():
        if info.filename!=entry:dst.writestr(info,src.read(info.filename))
    dst.write(client/'resourcepacks'/name,entry)
with zipfile.ZipFile(temp) as z:
    assert z.testzip() is None
    assert z.read(entry)==(client/'resourcepacks'/name).read_bytes()
os.replace(temp,archive)
print('Local RC animation repair replaced; archive CRC passed. Server and worlds unchanged.')
