"""Isolated local integration audit. Does not touch the server or source profile."""
import hashlib, json, os, pathlib, zipfile, urllib.request, concurrent.futures, sys

REPO = pathlib.Path(__file__).resolve().parents[1]
OUT = REPO / 'integration'
LOCAL = REPO / 'out' / 'integration'
PROFILES = pathlib.Path(os.environ['APPDATA']) / 'ModrinthApp' / 'profiles'
SOURCE = PROFILES / 'COBBLEVERSE 1.8 Snapshot Custom'
TARGET = PROFILES / 'COBBLEVERSE 1.8 Integrated Test'

def dump(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')

def api(route):
    req=urllib.request.Request('https://api.modrinth.com/v2/'+route, headers={'User-Agent':'Cobbleverse-local-integration/1.0'})
    with urllib.request.urlopen(req, timeout=90) as r: return json.load(r)

def digest(p, algo='sha256'):
    h=hashlib.new(algo)
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()

def mod(p):
    with zipfile.ZipFile(p) as z:
        if 'fabric.mod.json' not in z.namelist(): return {'filename':p.name,'error':'no Fabric metadata'}
        m=json.loads(z.read('fabric.mod.json'), strict=False)
        return dict(filename=p.name,sha256=digest(p),sha1=digest(p,'sha1'),size=p.stat().st_size,**{k:m.get(k) for k in ['id','version','environment','depends','breaks','conflicts','recommends','entrypoints','mixins','jars','contact']})

def audit():
    files=[]
    if (LOCAL/'source-all-files-private.json').exists():
        files=json.loads((LOCAL/'source-all-files-private.json').read_text(encoding='utf-8'))
    else:
        for p in sorted(SOURCE.rglob('*')):
            if p.is_file() and not p.is_symlink():
                files.append({'path':p.relative_to(SOURCE).as_posix(),'size':p.stat().st_size,'sha256':digest(p)})
    # Full profile hashes stay local: filenames can include player information.
    dump(LOCAL/'source-all-files-private.json', files)
    dump(OUT/'source-content-manifest.json',[f for f in files if f['path'].split('/')[0] in ['mods','config','datapacks','resourcepacks','defaultconfigs','fancymenu_data','legendary-monuments-data']])
    mods=[mod(p) for p in sorted((SOURCE/'mods').glob('*.jar'))]
    dump(OUT/'source-mods.json',mods)
    print('SOURCE files',len(files),'mods',len(mods),flush=True)
    def versions(slug):
        try:
            data=api('project/'+slug+'/version')
            compatible=[v for v in data if '1.21.1' in v['game_versions'] and 'fabric' in v['loaders']]
            dump(OUT/'official'/(slug+'.json'),compatible[:6])
            return slug,[(v['id'],v['version_number'],v['version_type']) for v in compatible[:3]]
        except Exception as e: return slug,str(e)
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for r in pool.map(versions,['cobbleverse','cobblemon','cobblemon-battle-tower','ftb-library','ftb-teams','ftb-quests','cobblemon-quests']): print(r,flush=True)
    candidates=[]
    for base in [pathlib.Path.home()/'Downloads',PROFILES,REPO.parent,pathlib.Path.home()/'Desktop'/'cobbleverse-for-chatgpt']:
        for d,dirs,names in os.walk(base):
            dirs[:]=[x for x in dirs if x not in ['world','world-backups','backups','.git','libraries','assets','region','node_modules'] and not x.startswith('world.')]
            for n in names:
                p=pathlib.Path(d)/n
                if 'quest' in n.lower() or '퀘스트' in n: candidates.append(str(p))
                if n.lower().endswith(('.zip','.mrpack')):
                    try:
                        with zipfile.ZipFile(p) as z:
                            q=[x for x in z.namelist() if 'ftbquests' in x.lower() or 'questbook' in x.lower()]
                            if q:candidates.append({'archive':str(p),'entries':q[:30]})
                    except (OSError,zipfile.BadZipFile): pass
    dump(LOCAL/'questbook-search-private.json',candidates)
    print('QUESTBOOK',json.dumps(candidates,ensure_ascii=False),flush=True)
    with zipfile.ZipFile(pathlib.Path.home()/'Desktop/cobbleverse-for-chatgpt/configs-text.zip') as z:
        dump(OUT/'reference-config-archive.json',{'entries':z.namelist(),'count':len(z.namelist())})
    print('AUDIT DONE',flush=True)

if __name__=='__main__': audit()
