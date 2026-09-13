"""Run a bounded engine operation with isolated data and inspect the actual log."""
from pathlib import Path
import argparse, os, subprocess, sys, time
from stage import ROOT, stage

def run(mode):
    project=stage()
    editor=ROOT/'work/switch-tools/godot-switch-v3.5.1-windows/godot.windows.opt.tools.64.exe'
    logs=ROOT/'work/switch-logs'
    logs.mkdir(parents=True,exist_ok=True)
    data=ROOT/'work/switch-userdata'
    data.mkdir(parents=True,exist_ok=True)
    env=os.environ.copy()
    env['XDG_DATA_HOME']=str(data)
    args=[str(editor),'--path',str(project),'--audio-driver','Dummy','--verbose']
    if mode!='capture':args+=['--no-window']
    if mode=='import':args+=['--editor','--script','tools/wait_import.gd']
    elif mode=='test':args+=['--disable-render-loop','--script','tests/check.gd','--self-test']
    elif mode=='capture':args+=['--script','tests/capture.gd','--self-test']
    elif mode=='smoke':args+=['--disable-render-loop','--script','tests/smoke.gd','--self-test']
    else:raise ValueError(mode)
    log=logs/(mode+'.log')
    with log.open('wb') as output:
        process=subprocess.Popen(args,cwd=ROOT,stdout=output,stderr=subprocess.STDOUT,
                                 env=env,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        started=time.monotonic()
        while process.poll() is None:
            time.sleep(0.5)
            current=log.read_text(encoding='utf-8',errors='replace')
            if 'SCRIPT ERROR:' in current or 'Parse Error' in current or time.monotonic()-started>300:
                process.kill()
                break
        process.wait(timeout=10)
    text=log.read_text(encoding='utf-8',errors='replace')
    print('\n'.join(text.splitlines()[-35:]))
    errors=[line for line in text.splitlines() if 'ERROR:' in line or 'Parse Error' in line]
    if errors: print('ERROR SUMMARY:\n'+'\n'.join(errors[:20]))
    if process.returncode or errors:raise SystemExit(2)
    expected={'import':'IRON_SWITCH_IMPORT_FINISHED','test':'IRON_SWITCH_CHECKS_PASSED',
              'capture':'IRON_SWITCH_CAPTURE_FINISHED','smoke':'IRON_SWITCH_SMOKE_FINISHED'}[mode]
    if expected not in text:raise SystemExit('Missing completion marker: '+expected)

if __name__=='__main__':
    sys.stdout.reconfigure(errors='replace')
    parser=argparse.ArgumentParser()
    parser.add_argument('mode',choices=['import','test','capture','smoke'])
    run(parser.parse_args().mode)
