"""Stage a Godot 3 project, reusing tracked PC source assets without modifying them."""
from pathlib import Path
import argparse, hashlib, json, re, shutil, zipfile

ROOT = Path(__file__).resolve().parents[2]

def copy_changed(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists() or hashlib.sha256(source.read_bytes()).digest() != hashlib.sha256(target.read_bytes()).digest():
        shutil.copy2(source, target)

def stage():
    target = ROOT / 'work/switch-project'
    authored = ROOT / 'switch-godot'
    for p in authored.rglob('*'):
        if p.is_file() and '__pycache__' not in p.parts:
            copy_changed(p, target / p.relative_to(authored))
    copy_changed(ROOT/'pc-godot/assets/branding/icon.svg',target/'assets/icon.svg')
    assets = ROOT / 'pc-godot/assets'
    folders = ['models/realistic', 'models/monsters', 'models/ordnance',
               'models/environment/polyhaven_tree_small02', 'models/environment/polyhaven_rock09',
               'models/environment/polyhaven_concrete_facade', 'models/environment/polyhaven_aerial_grass',
               'materials', 'fx/fluid', 'audio/combat', 'audio/battlefield']
    manifest = []
    for folder in folders:
        for p in (assets / folder).rglob('*'):
            if not p.is_file() or p.suffix in ('.import', '.uid', '.tres', '.tscn', '.gd', '.gdshader'):
                continue
            copy_changed(p, target / 'assets' / p.relative_to(assets))
            manifest.append({'source':p.relative_to(ROOT).as_posix(), 'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
    for name in ['vehicle_catalog', 'mission_catalog', 'woodland_layout']:
        source = (ROOT / 'pc-godot/data' / (name+'.gd')).read_text(encoding='utf-8')
        source = re.sub(r'^class_name .*\n','',source)
        source = source.replace('extends RefCounted','extends Reference').replace(':=','=')
        source = re.sub(r'Array\[[^\]]+\]', 'Array', source)
        source = re.sub(r'(for\s+\w+)\s*:\s*\w+(\s+in)',r'\1\2',source)
        for fn in ['clamp','min','max','abs','round','floor','ceil','snapped']:
            source = re.sub(r'\b'+fn+r'[fi]\(',fn+'(',source)
        # Godot 3 has no Vector4. Preserve the source tuple meaning explicitly.
        source = re.sub(r'Vector4\(([^)]+)\)',r'[\1]',source)
        for name4,i in [('x',0),('y',1),('z',2),('w',3)]: source=source.replace('hill.'+name4,'hill['+str(i)+']')
        (target/'data').mkdir(exist_ok=True)
        (target/'data'/(name+'.gd')).write_text(source,encoding='utf-8')
    (ROOT/'work/switch-asset-manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    return target

def tools(source):
    dest=ROOT/'work/switch-tools'
    dest.mkdir(parents=True,exist_ok=True)
    pins={'godot-v3.5.1-windows-switch-support.zip':'12e542b66e3a43874b5bb1d8db2f13dac960cfbf82ef3a7526c43005ffce06a5',
          'godot_template-v3.5.1-switch_only.tpz':'14dca7b9bd11ebb881658986de63bb666c4bd690cc8586fe5722fab9f4ea7957'}
    for filename,pin in pins.items():
        package=source/filename
        assert hashlib.sha256(package.read_bytes()).hexdigest()==pin, filename+' hash mismatch'
        with zipfile.ZipFile(package) as archive:
            for entry in archive.infolist():
                out=(dest/entry.filename).resolve()
                assert out.is_relative_to(dest.resolve())
                if not out.exists(): archive.extract(entry,dest)
    editor=dest/'godot-switch-v3.5.1-windows/godot.windows.opt.tools.64.exe'
    assert editor.exists()
    (editor.parent/'_sc_').touch()
    templates=dest/'templates'
    destination=editor.parent/'editor_data/templates'/(templates/'version.txt').read_text().strip()
    for p in templates.iterdir():
        if p.is_file():copy_changed(p,destination/p.name)
    return editor

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--tool-cache',type=Path)
    args=parser.parse_args()
    if args.tool_cache: print('EDITOR:',tools(args.tool_cache))
    print('PROJECT:',stage())
