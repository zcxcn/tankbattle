"""Export the verified community runtime, then validate every packed resource."""
from pathlib import Path
import argparse, datetime, hashlib, json, os, shutil, subprocess, sys, zipfile, time
from stage import ROOT, stage
from verify_switch import finalize_and_verify
from verify_imports import check_imports

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def execute(editor,project,args,name,marker=None):
    environment=os.environ.copy()
    environment['XDG_DATA_HOME']=str(ROOT/'work/switch-userdata')
    log=ROOT/'work/switch-logs'/(name+'.log')
    with log.open('wb') as output:
        process=subprocess.Popen([str(editor),'--no-window','--audio-driver','Dummy','--path',str(project),'--verbose',*args],
                                 stdout=output,stderr=subprocess.STDOUT,env=environment,
                                 creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        started=time.monotonic()
        while process.poll() is None:
            time.sleep(0.5)
            current=log.read_text(encoding='utf-8',errors='replace')
            if 'SCRIPT ERROR:' in current or 'Parse Error' in current or time.monotonic()-started>300:
                process.kill()
                break
        process.wait(timeout=10)
    text=log.read_text(encoding='utf-8',errors='replace')
    errors=[line for line in text.splitlines() if 'ERROR:' in line or 'Parse Error' in line]
    if process.returncode or errors or (marker and marker not in text):
        print('\n'.join(text.splitlines()[-30:]))
        raise RuntimeError(name+' failed: '+str(errors[:5]))

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--skip-tests',action='store_true')
    args=parser.parse_args()
    project=stage()
    editor=ROOT/'work/switch-tools/godot-switch-v3.5.1-windows/godot.windows.opt.tools.64.exe'
    template=ROOT/'work/switch-tools/templates/switch_release.nro'
    assert editor.exists() and template.exists(),'Run stage.py --tool-cache <verified archive directory> first'
    (ROOT/'work/switch-logs').mkdir(parents=True,exist_ok=True)
    sources={p.relative_to(ROOT).as_posix():sha(p) for p in (ROOT/'switch-godot').rglob('*') if p.is_file() and '__pycache__' not in p.parts}
    execute(editor,project,['--editor','--script','tools/wait_import.gd'],'final-import','IRON_SWITCH_IMPORT_FINISHED')
    execute(editor,project,['--disable-render-loop','--script','tools/icon.gd'],'icon','IRON_SWITCH_ICON_READY')
    subprocess.run(['pwsh','-NoProfile','-File',str(ROOT/'switch-godot/tools/icon.ps1'),
                    '-Source',str(project/'assets/icon-export.png'),'-Destination',str(project/'assets/icon.jpg')],check=True)
    execute(editor,project,['--editor','--script','tools/wait_import.gd'],'icon-import','IRON_SWITCH_IMPORT_FINISHED')
    if not args.skip_tests:
        execute(editor,project,['--disable-render-loop','--script','tests/check.gd','--self-test'],'final-check','IRON_SWITCH_CHECKS_PASSED')
        execute(editor,project,['--disable-render-loop','--script','tests/smoke.gd','--self-test'],'final-smoke','IRON_SWITCH_SMOKE_FINISHED')
    imports=check_imports(project)
    output=ROOT/'outputs/switch/IronEmbers'
    output.mkdir(parents=True,exist_ok=True)
    nro=output/'IronEmbers.nro'
    for p in [nro,nro.with_suffix('.pck')]:p.unlink(missing_ok=True)
    execute(editor,project,['--export','Switch',str(nro)],'export')
    assert imports==check_imports(project),'Assets changed during export'
    assert sources=={p:sha(ROOT/p) for p in sources},'Source changed during export'
    report=finalize_and_verify(nro,template,'钢铁余烬 · Switch','Iron Embers Build','0.1.0')
    report['source_files']=sources
    (output/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    (output/'import-validation.json').write_text(json.dumps(imports,indent=2),encoding='utf-8')
    shutil.copy2(ROOT/'switch-godot/README.md',output/'README.md')
    for p in (ROOT/'switch-godot/tools').glob('GODOT-*.txt'):shutil.copy2(p,output/p.name)
    shutil.copy2(ROOT/'switch-godot/tools/toolchain-lock.json',output/'toolchain-lock.json')
    # Keep source model, recording, font and VFX attribution outside the pack too.
    for p in (project/'assets').rglob('*'):
        if p.is_file() and p.suffix.lower() in ('.md','.txt'):
            dest=output/'credits'/p.relative_to(project/'assets')
            dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(p,dest)
    archive=ROOT/'outputs/switch/Iron-Embers-Switch1-0.1.0.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for p in sorted(output.rglob('*')):
            if p.is_file():z.write(p,'switch/IronEmbers/'+p.relative_to(output).as_posix())
    with zipfile.ZipFile(archive) as z:assert z.testzip() is None
    summary={'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'nro_bytes':nro.stat().st_size,
             'pck_bytes':nro.with_suffix('.pck').stat().st_size,'zip_bytes':archive.stat().st_size,
             'zip_sha256':sha(archive),'hardware_execution_verified':False}
    (ROOT/'outputs/switch/build-summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print(json.dumps(summary,indent=2))

if __name__=='__main__':
    sys.stdout.reconfigure(errors='replace')
    main()
