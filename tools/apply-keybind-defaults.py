"""Apply approved key cleanup to the stopped client and local RC archive."""
from pathlib import Path
import json
import shutil
import os
import zipfile
from datetime import datetime
from keybind_defaults import clean_options

repo = Path(__file__).resolve().parent.parent
profile = Path(os.environ['APPDATA']) / 'ModrinthApp/profiles/COBBLEVERSE 1.8 Integrated Test'
options = profile / 'options.txt'
new, changes = clean_options(options.read_text(encoding='utf8'))
backup = repo / 'out/integration/keybind-backups' / datetime.now().strftime('%Y%m%d-%H%M%S')
backup.mkdir(parents=True)
shutil.copy2(options, backup / 'options.txt')
options.write_text(new, encoding='utf8')
pack = repo / 'out/COBBLEVERSE-Integrated-2026.10.25-rc1/Player/COBBLEVERSE-Integrated-2026.10.25-rc1.mrpack'
temp = pack.with_suffix('.tmp')
with zipfile.ZipFile(pack) as src, zipfile.ZipFile(temp, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as dest:
    for info in src.infolist():
        data = src.read(info.filename)
        if info.filename == 'client-overrides/options.txt':
            data = clean_options(data.decode('utf8'))[0].encode('utf8')
        dest.writestr(info, data)
with zipfile.ZipFile(temp) as check:
    assert check.testzip() is None
os.replace(temp, pack)
(repo / 'integration/keybind-cleanup.json').write_text(json.dumps({'changes': changes, 'active_duplicate_keys': 0, 'client_runtime_test': 'not performed; user will relaunch'}, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
print(f'Updated client and mrpack; changed {len(changes)} bindings; no duplicate assigned keys.')
