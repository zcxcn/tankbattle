"""Run with Blender --background --python scripts/prepare-woodland-tree.py.

Input: verified Poly Haven Tree Small 02 glTF under work/asset-review/woodland/source.
Output: reusable terrain tree with original UV/PBR textures and bounded geometry.
"""
import bpy
import json
import pathlib
from mathutils import Vector

root = pathlib.Path(__file__).resolve().parents[1]
source = root / 'work/asset-review/woodland/source/tree_small_02_1k.gltf'
output = root / 'pc-godot/assets/models/environment/polyhaven_tree_small02'
output.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(source))
objects = [o for o in bpy.context.scene.objects if o.type == 'MESH']
report = []
for obj in objects:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    # Simplify the authored branch/leaf mesh, preserving its UVs and materials.
    original = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    modifier = obj.modifiers.new('ForestMeshBudget', 'DECIMATE')
    modifier.ratio = min(1.0, 65000.0 / original)
    modifier.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bounds = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    min_z = min(p.z for p in bounds)
    height = max(p.z for p in bounds) - min_z
    # A consistent 16 m source; runtime trees vary in height and crown width.
    scale = 16.0 / height
    obj.location.z -= min_z
    obj.scale *= scale
    obj.location *= scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    report.append({'source_triangles': original, 'triangles': sum(len(p.vertices)-2 for p in obj.data.polygons), 'source_height': height})
bpy.ops.export_scene.gltf(filepath=str(output / 'woodland_tree.glb'), export_format='GLB', export_yup=True, export_apply=True)
(output / 'conversion.json').write_text(json.dumps(report, indent=2), encoding='utf8')
print('WOODLAND_TREE_READY', json.dumps(report), flush=True)
