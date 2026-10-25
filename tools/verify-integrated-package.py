"""Check local distribution contents; never starts Minecraft or sends files."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import zipfile
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--allow-server-runtime-data', action='store_true',
                    help='Server folder has already been used; still check mod hashes, but permit its generated world and logs.')
args = parser.parse_args()

repo = Path(__file__).resolve().parent.parent
root = repo / 'out/COBBLEVERSE-Integrated-2026.10.25-rc1'
manifest = json.loads((repo / 'integration/release-mod-manifest.json').read_text(encoding='utf8'))
by_name = {m['filename']: m for m in manifest}
pack = next((root / 'Player').glob('*.mrpack'))
forbidden = {'saves', 'logs', 'crash-reports', 'accounts.json', 'integration-verification-only'}
with zipfile.ZipFile(pack) as z:
    assert z.testzip() is None
    names = z.namelist()
    assert len(names) == len(set(names))
    for name in names:
        path = PurePosixPath(name)
        assert not path.is_absolute() and '..' not in path.parts
        assert not forbidden.intersection(p.lower() for p in path.parts), name
        assert not name.endswith(('.disabled', '.log')), name
    index = json.loads(z.read('modrinth.index.json'))
    assert index['dependencies'] == {'minecraft': '1.21.1', 'fabric-loader': '0.18.4'}
    packaged = set()
    for f in index['files']:
        name = PurePosixPath(f['path']).name
        assert f['hashes']['sha512'] == by_name[name]['sha512']
        assert f['fileSize'] == by_name[name]['size']
        assert f['downloads'] and all(u.startswith('https://') for u in f['downloads'])
        packaged.add(name)
    for name in names:
        if name.startswith(('overrides/mods/', 'client-overrides/mods/')) and name.endswith('.jar'):
            filename = PurePosixPath(name).name
            assert hashlib.sha256(z.read(name)).hexdigest() == by_name[filename]['sha256']
            assert filename not in packaged
            packaged.add(filename)
    assert packaged == set(by_name)
server = root / 'Server'
server_mods = list((server / 'mods').glob('*.jar'))
assert len(server_mods) == sum(m['server_included'] for m in manifest)
for p in server_mods:
    m = by_name[p.name]
    assert m['server_included'] and m['environment'] != 'client'
    assert hashlib.sha256(p.read_bytes()).hexdigest() == m['sha256']
if not args.allow_server_runtime_data:
    for p in server.rglob('*'):
        assert not forbidden.intersection(part.lower() for part in p.relative_to(server).parts), p
    assert 'eula=false' in (server / 'eula.txt').read_text()
report = {'archive_integrity': 'passed', 'client_mods': len(packaged), 'server_mods': len(server_mods),
          'mod_hashes': 'passed', 'excluded_private_runtime_paths': 'passed for mrpack',
          'server_runtime_paths': 'not checked; server already used' if args.allow_server_runtime_data else 'passed',
          'mrpack_bytes': pack.stat().st_size, 'mrpack_sha256': hashlib.sha256(pack.read_bytes()).hexdigest(),
          'runtime_test': 'not performed by this check'}
(repo / 'integration/package-verification.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf8')
print(json.dumps(report, indent=2))
