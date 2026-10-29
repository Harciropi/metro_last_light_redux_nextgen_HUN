"""Stage the current payload in a caller-owned, empty temporary directory."""
from pathlib import Path
import argparse,json,hashlib,shutil
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--output',required=True,type=Path)
OUT=parser.parse_args().output.resolve()
if OUT.is_symlink() or (OUT.exists() and any(OUT.iterdir())):
    raise SystemExit('The staging directory must be empty.')
PAYLOAD=OUT/'payload';PAYLOAD.mkdir(parents=True,exist_ok=True)
shutil.copy2(ROOT/'installer/metro.ico',OUT/'metro.ico')
shutil.copy2(ROOT/'installer/intaller_image.bmp',OUT/'intaller_image.bmp')
inputs=json.loads((ROOT/'installer/payload-files.json').read_text(encoding='utf8'))
files=[]
def add(source,name,role,resource=None):
    target=PAYLOAD/name;shutil.copy2(source,target)
    files.append({'Name':name,'Role':role,'Resource':resource,'Sha256':hashlib.sha256(target.read_bytes()).hexdigest().upper()})
add(ROOT/'installer/Resources.cs','Resources.cs','Helper')
for f in inputs:add(ROOT/'installer/payload'/f['Name'],f['Name'],f['Role'],f['Resource'])
version=(ROOT/'VERSION').read_text(encoding='utf8').strip()
manifest={'Product':'Harciropi.MetroLastLightRedux.NextGen.HU','Version':version,'Files':files,'Attribution':{'OriginalTranslation':'Lostprophet','NextGenTranslationAndInstaller':'Harciropi'}}
manifest_bytes=json.dumps(manifest,ensure_ascii=False,indent=2).encode('utf8');(PAYLOAD/'package.json').write_bytes(manifest_bytes)
manifest_hash=hashlib.sha256(manifest_bytes).hexdigest().upper()
backend=(ROOT/'installer/Kezeles.ps1').read_text(encoding='utf-8-sig').replace('@@MANIFEST_SHA256@@',manifest_hash)
(OUT/'Kezeles.ps1').write_text(backend,encoding='utf-8-sig')
print(json.dumps({'version':version,'files':len(files),'manifest_sha256':manifest_hash,'output':str(OUT)}))
