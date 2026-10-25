"""Isolated local integration audit. Does not touch the server or source profile."""
import hashlib, json, os, pathlib, zipfile, urllib.request, concurrent.futures, sys, shutil

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

def download_version(v):
    f=next((f for f in v['files'] if f.get('primary')),v['files'][0])
    dest=LOCAL/'downloads'/f['filename']
    dest.parent.mkdir(parents=True,exist_ok=True)
    if not dest.exists():
        print('DOWNLOAD',f['filename'],flush=True)
        urllib.request.urlretrieve(f['url'],dest)
    for algo,h in f['hashes'].items():
        if digest(dest,algo)!=h:raise ValueError('Download hash mismatch: '+str(dest))
    return dest

def prepare():
    if TARGET.exists():raise RuntimeError('Target already exists; refusing overwrite')
    if not (LOCAL/'source-all-files-private.json').exists():raise RuntimeError('Run audit before prepare')
    TARGET.mkdir()
    for name in ['mods','config','datapacks','resourcepacks','defaultconfigs','fancymenu_data','licenses','shaderpacks']:
        if (SOURCE/name).exists():shutil.copytree(SOURCE/name,TARGET/name)
    # Copy options only, never account data, worlds, logs, caches or updater identity.
    shutil.copy2(SOURCE/'options.txt',TARGET/'options.txt')
    additions=[]
    downloads=pathlib.Path.home()/'Downloads'
    for name in ['ftb-library-fabric-2101.1.37.jar','ftb-teams-fabric-2101.1.11.jar','ftb-quests-fabric-2101.1.37.jar','cobblemon-pc-enhancements-1.1.0.jar']:
        src=downloads/name
        shutil.copy2(src,TARGET/'mods'/name)
        additions.append(dict(source='user-supplied-download',**mod(src)))
    q=downloads/'Cobbleverse Questsbook v4.1.zip'
    with zipfile.ZipFile(q) as z:
        for entry in z.infolist():
            if entry.is_dir():continue
            rel=pathlib.PurePosixPath(entry.filename)
            if rel.is_absolute() or '..' in rel.parts or rel.parts[0] not in ['config','resourcepacks']:raise ValueError('Unsafe questbook entry')
            dest=TARGET.joinpath(*rel.parts)
            dest.parent.mkdir(parents=True,exist_ok=True)
            dest.write_bytes(z.read(entry))
    options=TARGET/'options.txt'
    lines=options.read_text(encoding='utf-8').splitlines()
    for i,line in enumerate(lines):
        if line.startswith('resourcePacks:'):
            packs=json.loads(line.split(':',1)[1]); pack='file/!Cobbleverse Questsbook Resourcepack.zip'
            if pack not in packs:packs.append(pack)
            lines[i]='resourcePacks:'+json.dumps(packs,ensure_ascii=False,separators=(',',':'))
    options.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    dump(OUT/'questbook-input.json',{'filename':q.name,'sha256':digest(q),'status':'installed; runtime validation pending','chapters':len(list((TARGET/'config/ftbquests/quests/chapters').glob('*.snbt')))})
    for slug in ['cobblemon-battle-tower','cobblemon-quests']:
        versions=json.loads((OUT/'official'/(slug+'.json')).read_text(encoding='utf-8'))
        v=versions[0]; src=download_version(v)
        shutil.copy2(src,TARGET/'mods'/src.name)
        additions.append(dict(project_id=v['project_id'],version_id=v['id'],downloads=v['files'],**mod(src)))
    dump(OUT/'added-mods.json',additions)
    dump(OUT/'prepared-mods.json',[mod(p) for p in sorted((TARGET/'mods').glob('*.jar'))])
    print('PREPARED',str(TARGET),flush=True)
    for a in additions:print(a['id'],a['version'],a['depends'],flush=True)

if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='prepare':prepare()
    else:audit()
