from pathlib import Path
import zipfile,json,shutil,os

repo=Path(__file__).resolve().parent.parent
profile=Path(os.environ['APPDATA'])/'ModrinthApp/profiles/COBBLEVERSE 1.8 Integrated Test'
root=Path(os.environ.get('COBBLEVERSE_REPAIR_TEST_ROOT',repo/'out/client-animation-repair-tests'));root.mkdir(exist_ok=True)
animation='assets/cobblemon/bedrock/pokemon/animations/0753_fomantis/fomantis.animation.json'
with zipfile.ZipFile(profile/'mods/Cobblemon-fabric-1.8.3+1.21.1.jar') as z:
    base=z.read(animation)
    callback=z.read('com/cobblemon/mod/common/events/CallbackHandler.class')
    base_poser=z.read('assets/cobblemon/bedrock/pokemon/posers/0753_fomantis/fomantis.json')
    vileplume_entry='assets/cobblemon/bedrock/pokemon/animations/0045_vileplume/vileplume.animation.json'
    vileplume_base=z.read(vileplume_entry)
with zipfile.ZipFile(profile/'resourcepacks/ATMxMSD RP.zip') as z:
    atm=z.read(animation)
    atm_poser=z.read('assets/cobblemon/bedrock/pokemon/posers/0753_fomantis/fomantis2.json')
with zipfile.ZipFile(profile/'resourcepacks/COBBLEVERSE-ko_kr-cobblemon1.8-fixed.zip') as z:
    translation=z.read(animation)
    vileplume_translation=z.read(vileplume_entry)
backups=sorted((repo/'out/integration/runtime-fix-backups').glob('*/client/config/resourcepackoverrides.json'))
if backups:
    original_config=backups[0].read_bytes()
else:
    # A fresh checkout can still exercise both reported serialization failures.
    original_config=json.dumps({'schema_version':'2','default_packs':['vanilla'],
      'pack_overrides':{'file/example.zip':{'title':'Plain component title','description':'"Line one\nLine two"'}},
      'default_overrides':{}},ensure_ascii=False).encode('utf8')
for case in ['success','bad-hash','running','directory']:
    p=root/case
    for folder in ['mods','config','resourcepacks','world']: (p/folder).mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(p/'mods/renamed-core.jar','w') as z:
        z.writestr('fabric.mod.json',json.dumps({'id':'cobblemon','version':'1.8.3+1.21.1'}));z.writestr(animation,base)
        z.writestr('com/cobblemon/mod/common/events/CallbackHandler.class',callback)
        z.writestr('assets/cobblemon/bedrock/pokemon/posers/0753_fomantis/fomantis.json',base_poser)
        z.writestr(vileplume_entry,vileplume_base)
        z.writestr('assets/cobblemon/bedrock/pokemon/animations/a/fixture.animation.json',json.dumps({'format_version':'1.8.0','animations':{'animation.fixture.old':{'loop':True},'animation.fixture.shared':{'animation_length':1}}}))
    for name,raw in [('ATM fixture.zip',atm),('Korean fixture.zip',translation)]:
        with zipfile.ZipFile(p/'resourcepacks'/name,'w') as z:
            z.writestr(animation,raw)
            if name=='Korean fixture.zip':
                z.writestr(vileplume_entry,vileplume_translation)
                z.writestr('assets/cobblemon/bedrock/pokemon/animations/z/fixture.animation.json',json.dumps({'format_version':'1.8.0','animations':{'animation.fixture.new':{'loop':False},'animation.fixture.shared':{'animation_length':2}}}))
            if name=='ATM fixture.zip':z.writestr('assets/cobblemon/bedrock/pokemon/posers/0753_fomantis/fomantis2.json',atm_poser)
    text='mouseSensitivity:0.373\nguiScale:2\nkey_key.cobblemon.summary:key.keyboard.c\nresourcePacks:["vanilla","file/ATM fixture.zip","file/Korean fixture.zip"]\n'
    if case=='directory':
        text=text.replace('file/Korean fixture.zip','file/Folder fixture')
        folder=p/'resourcepacks/Folder fixture/assets/cobblemon/bedrock/pokemon/animations'
        folder.mkdir(parents=True,exist_ok=True)
        (folder/'fixture.animation.json').write_text('{"animations":{}}',encoding='utf8')
    (p/'options.txt').write_text(text,encoding='utf8')
    (p/'config/resourcepackoverrides.json').write_bytes(original_config)
    (p/'world/progress.txt').write_text('KEEP PLAYER PROGRESS\n',encoding='utf8')
    (p/'original-options.txt').write_text(text,encoding='utf8')
    (p/'original-resourcepackoverrides.json').write_bytes(original_config)
(root/'bad-artifact.jar').write_bytes(b'Not a trusted mod')
print('Prepared isolated resource/config fixtures from the actual conflicting packs.')
