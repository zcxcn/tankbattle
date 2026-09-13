"""Package the exact verified game and its independently verified HOME helper."""
from pathlib import Path
import hashlib, json, zipfile

ROOT=Path(__file__).resolve().parents[1]
OUTPUT=ROOT/'outputs/switch'

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    game=OUTPUT/'IronEmbers'
    helper=ROOT/'outputs/switch-home/IronEmbersHome'
    validation=json.loads((game/'validation.json').read_text(encoding='utf-8'))
    smoke=json.loads((OUTPUT/'package-smoke.json').read_text(encoding='utf-8'))
    helper_check=json.loads((helper/'IronEmbersHome.verification.json').read_text(encoding='utf-8'))
    assert validation['pck']['sha256']==smoke['pck_sha256']==sha(game/'IronEmbers.pck')
    assert validation['nro']['sha256']==sha(game/'IronEmbers.nro')
    assert helper_check['output_sha256']==sha(helper/'IronEmbersHome.nro')
    assert smoke['status']=='passed'
    files={}
    for source,prefix in [(game,'switch/IronEmbers'),(helper,'switch/IronEmbersHome')]:
        for path in source.rglob('*'):
            if path.is_file():files[prefix+'/'+path.relative_to(source).as_posix()]=path
    files['START-HERE.md']=ROOT/'docs/switch1/INSTALL.md'
    files['VALIDATION.md']=ROOT/'docs/switch1/SELF_CHECK_0.1.0.md'
    archive=OUTPUT/'Iron-Embers-Switch1-0.1.0-Complete.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for name,path in sorted(files.items()):z.write(path,name)
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for name,path in files.items():assert hashlib.sha256(z.read(name)).hexdigest()==sha(path)
    report={'file':archive.name,'bytes':archive.stat().st_size,'sha256':sha(archive),
            'entries':len(files),'all_archived_contents_sha256_match':True}
    (OUTPUT/'complete-package.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report,indent=2))

if __name__=='__main__':main()
