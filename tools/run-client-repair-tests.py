"""Run isolated updater tests in Windows PowerShell 5.1, without launching Minecraft."""
from pathlib import Path
import subprocess,sys,hashlib,os,tempfile
repo=Path(__file__).resolve().parent.parent
root=Path(tempfile.mkdtemp(prefix='client-animation-tests-',dir=repo/'out'))
os.environ['COBBLEVERSE_REPAIR_TEST_ROOT']=str(root)
subprocess.run([sys.executable,str(repo/'tools/prepare-client-repair-tests.py')],check=True)
script=repo/'updater/Cobbleverse-ClientRepairs.ps1'
artifact=repo/'out/client-callback-guard/cobbleverse-client-callback-guard-1.0.0.jar'
def run(case,bad=False,running=False):
    # The only mocked API is process discovery. No game process is created.
    mock="[pscustomobject]@{CommandLine='net.minecraft.client.main.Main'}" if running else ''
    command=f"function global:Get-CimInstance {{ {mock} }}; & '{script}' -ProfilePath '{root/case}' -LocalHotfixPath '{root/'bad-artifact.jar' if bad else artifact}'"
    env=os.environ.copy()
    # PowerShell 7's inherited module path can hide Windows PowerShell 5 modules.
    env.pop('PSModulePath',None)
    return subprocess.run(['powershell.exe','-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-Command',command],env=env,check=False).returncode
assert run('success')==0
files=[root/'success'/name for name in ['options.txt','config/resourcepackoverrides.json','resourcepacks/Cobbleverse-Client-Repair-2026.10.27.zip']]
before=[hashlib.sha256(p.read_bytes()).hexdigest() for p in files]
backups=set((root/'success').glob('.cobbleverse-client-repair-*'))
assert run('success')==0
assert before==[hashlib.sha256(p.read_bytes()).hexdigest() for p in files]
assert backups==set((root/'success').glob('.cobbleverse-client-repair-*'))
assert run('bad-hash',bad=True)!=0
assert run('running',running=True)!=0
assert run('directory')!=0
subprocess.run([sys.executable,str(repo/'tools/verify-client-repair-tests.py')],check=True)
