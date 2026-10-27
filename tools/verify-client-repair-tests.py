from pathlib import Path
import zipfile,json,hashlib

repo=Path(__file__).resolve().parent.parent
root=repo/'out/client-repair-tests';p=root/'success'
addon=p/'mods/cobbleverse-client-callback-guard-1.0.0.jar'
expected=json.loads((repo/'out/client-callback-guard/artifact.json').read_text())['sha256']
assert hashlib.sha256(addon.read_bytes()).hexdigest()==expected
cfg=json.loads((p/'config/resourcepackoverrides.json').read_text(encoding='utf8'))
fixed=0
for fields in list(cfg['pack_overrides'].values())+[cfg['default_overrides']]:
    for key in ['title','description']:
        if isinstance(fields.get(key),str):json.loads(fields[key]);fixed+=1
pack=p/'resourcepacks/Cobbleverse-Client-Repair-2026.10.27.zip'
with zipfile.ZipFile(pack) as z:
    assert z.testzip() is None
    animations=json.loads(z.read('assets/cobblemon/bedrock/pokemon/animations/0753_fomantis/fomantis.animation.json'))['animations']
    for n in ['battle_idle','eyes_angry','eyes_quirk','blink','quirk','flowering','wild_sleep']:
        assert 'animation.fomantis.'+n in animations
old=(p/'original-options.txt').read_text();new=(p/'options.txt').read_text()
assert [s for s in old.splitlines() if not s.startswith('resourcePacks:')]==[s for s in new.splitlines() if not s.startswith('resourcePacks:')]
backups=[b for b in p.glob('.cobbleverse-client-repair-*') if (b/'options.txt').exists()]
assert len(backups)==1, 'Second invocation should not create another backup'
for case in ['bad-hash','running']:
    f=root/case
    assert (f/'options.txt').read_bytes()==(f/'original-options.txt').read_bytes()
    assert (f/'config/resourcepackoverrides.json').read_bytes()==(f/'original-resourcepackoverrides.json').read_bytes()
    assert not (f/'mods/cobbleverse-client-callback-guard-1.0.0.jar').exists()
    assert not (f/'resourcepacks/Cobbleverse-Client-Repair-2026.10.27.zip').exists()
for case in ['success','bad-hash','running']:
    assert (root/case/'world/progress.txt').read_text()=='KEEP PLAYER PROGRESS\n'
report={'resource_merge_and_required_animations':'passed','strict_text_components_checked':fixed,
        'personal_options_preserved':'passed','world_marker_preserved':'passed',
        'bad_hash_no_installed_changes':'passed','running_client_no_changes':'passed',
        'second_run_idempotent':'passed','backups':'passed','actual_gameplay':'not tested'}
(repo/'integration/client-repair-updater-verification.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
print(json.dumps(report,indent=2))
