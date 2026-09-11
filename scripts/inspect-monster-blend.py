"""Inspect downloaded artwork without enabling embedded Python scripts."""
import bpy
import json

print(json.dumps({
    "objects": [{"name": o.name, "type": o.type, "dimensions": list(o.dimensions),
                 "location": list(o.location),
                 "modifiers": [m.type for m in o.modifiers],
                 "materials": [m.name if m else None for m in o.data.materials] if o.type == 'MESH' else [],
                 "bones": [b.name for b in o.data.bones] if o.type == 'ARMATURE' else []}
                for o in bpy.data.objects],
    "images": [{"name": i.name, "path": i.filepath, "packed": bool(i.packed_file), "size": list(i.size)} for i in bpy.data.images],
    "actions": [{"name": a.name, "frames": list(a.frame_range)} for a in bpy.data.actions],
}, indent=2))
