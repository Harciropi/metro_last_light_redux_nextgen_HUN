"""Extract and verify the current EXE; does not access an installed game."""
from pathlib import Path
import argparse,hashlib,json,re,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
version=(ROOT/'VERSION').read_text(encoding='utf8').strip()
parser=argparse.ArgumentParser();parser.add_argument('--exe',type=Path);args=parser.parse_args()
exe=args.exe or ROOT/f'dist/v{version}/MetroLastLightRedux_NextGen_HU.exe'
tool=shutil.which('7z') or str(ROOT/'.private/tools/7zip/full/7z.exe')
with tempfile.TemporaryDirectory(prefix='MetroLastLightHuVerify-') as folder:
    target=Path(folder)
    subprocess.run([tool,'x',str(exe),'-o'+str(target),'-y','-bso0','-bsp0'],check=True)
    base=target/'$PLUGINSDIR';payload=base/'payload'
    manifest=json.loads((payload/'package.json').read_text(encoding='utf8'))
    sha=lambda b:hashlib.sha256(b).hexdigest().upper()
    assert manifest['Version']==version and len(manifest['Files'])==9
    for f in manifest['Files']:
        data=(payload/f['Name']).read_bytes();assert sha(data)==f['Sha256']
        source=ROOT/'installer/Resources.cs' if f['Role']=='Helper' else ROOT/'installer/payload'/f['Name']
        assert source.read_bytes()==data
    backend=(base/'Kezeles.ps1').read_text(encoding='utf-8-sig')
    assert re.search(r"\$TrustedManifestHash='([A-F0-9]{64})'",backend)[1]==sha((payload/'package.json').read_bytes())
    assert (base/'modern-wizard.bmp').read_bytes()==(ROOT/'installer/intaller_image.bmp').read_bytes()
    assert not list(target.rglob('pros.sdk.x64.dll')) and not list(target.rglob('metro.exe'))
    report={'version':version,'payload_files_verified':9,'bitmap_verified':True,'original_executable_and_sdk_not_distributed':True,'exe_sha256':sha(exe.read_bytes())}
    print(json.dumps(report,indent=2))
