"""Blender --background --disable-autoexec source.blend --python this.py -- role output.glb.
Preserve licensed authored geometry, skin, UVs and sampled walking animation.
"""
import bpy
import json
import math
import pathlib
import struct
import sys
from mathutils import Vector

role, output = sys.argv[sys.argv.index('--') + 1:]
if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
meshes = [o for o in bpy.data.objects if o.type == 'MESH'
          and any(m.type == 'ARMATURE' and m.object == rig for m in o.modifiers)]
assert meshes, 'No authored skinned meshes'
for collection in bpy.data.collections:
    collection.hide_viewport = False
for obj in [rig] + meshes:
    obj.hide_set(False)
    obj.hide_viewport = False
    obj.hide_render = False
for obj in list(bpy.data.objects):
    if obj not in meshes and obj != rig:
        bpy.data.objects.remove(obj, do_unlink=True)
# glTF skin export does not evaluate topology-changing modifiers automatically.
# Bake the authored symmetric half before exporting weights, retaining the rig.
for mesh in meshes:
    bpy.context.view_layer.objects.active = mesh
    for modifier in list(mesh.modifiers):
        if modifier.type == 'MIRROR':
            bpy.ops.object.modifier_apply(modifier=modifier.name)
rig.animation_data_create()
walk = next(a for a in bpy.data.actions if 'walk' in a.name.lower())
rig.animation_data.action = walk
if walk.slots:
    rig.animation_data.action_slot = walk.slots[0]
for track in rig.animation_data.nla_tracks:
    track.mute = True
bpy.context.scene.frame_start = max(0, int(walk.frame_range[0]))
bpy.context.scene.frame_end = int(walk.frame_range[1])

def pbr(name, diffuse, normal=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    surface = nodes.get('Principled BSDF')
    surface.inputs['Roughness'].default_value = .84
    diffuse.colorspace_settings.name = 'sRGB'
    tex = nodes.new('ShaderNodeTexImage')
    tex.image = diffuse
    links.new(tex.outputs['Color'], surface.inputs['Base Color'])
    if normal:
        normal.colorspace_settings.name = 'Non-Color'
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = normal
        node = nodes.new('ShaderNodeNormalMap')
        node.inputs['Strength'].default_value = .82
        links.new(tex.outputs['Color'], node.inputs['Color'])
        links.new(node.outputs['Normal'], surface.inputs['Normal'])
    return mat

if role == 'glutton':
    skin = pbr('GluttonAuthoredSkin', bpy.data.images['gluttonPaint.png'], bpy.data.images['paint'])
    for mesh in meshes:
        mesh.data.materials.clear()
        mesh.data.materials.append(skin)
        for face in mesh.data.polygons:
            face.material_index = 0
            face.use_smooth = True
else:
    skin = pbr('GolemAuthoredStone', bpy.data.images['GolemTex_v9.png'], bpy.data.images['GolemTex_norm_V6'])
    for mesh in meshes:
        mesh.data.materials.clear()
        mesh.data.materials.append(skin)
        for face in mesh.data.polygons:
            face.material_index = 0

bpy.context.scene.frame_set(bpy.context.scene.frame_start)
bpy.context.view_layer.update()
points = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
low, high = min(p.z for p in points), max(p.z for p in points)
wrapper = bpy.data.objects.new('NormalizedCreature', None)
bpy.context.collection.objects.link(wrapper)
for obj in [rig] + meshes:
    if obj.parent is None:
        transform = obj.matrix_world.copy()
        obj.parent = wrapper
        obj.matrix_world = transform
wrapper.scale = (1 / (high-low),) * 3
wrapper.location.z = -low / (high-low)
wrapper.rotation_euler.z = math.pi
bpy.ops.object.select_all(action='DESELECT')
for obj in [rig, wrapper] + meshes:
    obj.select_set(True)
path = pathlib.Path(output).resolve()
path.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
    export_animations=True, export_animation_mode='ACTIVE_ACTIONS', export_frame_range=True,
    export_force_sampling=True, export_skins=True, export_rest_position_armature=True,
    export_image_format='AUTO')
raw = path.read_bytes()
size = struct.unpack_from('<I', raw, 12)[0]
doc = json.loads(raw[20:20+size])
assert doc.get('skins') and doc.get('animations'), 'Missing skin or animation'
for animation in doc['animations']:
    animation['name'] = 'Walk'
chunk = json.dumps(doc, separators=(',', ':')).encode()
chunk += b' ' * ((-len(chunk)) % 4)
tail = raw[20+size:]
path.write_bytes(struct.pack('<4sII', b'glTF', 2, 20+len(chunk)+len(tail))
                 + struct.pack('<I4s', len(chunk), b'JSON') + chunk + tail)
print('COLOSSAL_EXPORT_COMPLETE', role, path.stat().st_size, 'source_height', high-low)
