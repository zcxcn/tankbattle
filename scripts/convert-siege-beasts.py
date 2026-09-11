"""Blender --background --disable-autoexec source.blend --python this.py -- role output.glb.

Retains authored meshes/UVs/normal maps, rebuilds legacy materials for glTF,
normalizes feet/height, and exports only game artwork. Reptile gains a skinned
tail and dorsal scutes plus a deterministic walk. See asset CREDITS.md.
"""
import bpy
import bmesh
import json
import math
import pathlib
import sys
import struct
from mathutils import Vector

role, output = sys.argv[sys.argv.index('--') + 1:]
if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
meshes = [o for o in bpy.data.objects if o.type == 'MESH' and any(m.type == 'ARMATURE' for m in o.modifiers)]
for collection in bpy.data.collections:
    collection.hide_viewport = False
for obj in [rig] + meshes:
    obj.hide_set(False)
    obj.hide_viewport = False
for o in list(bpy.data.objects):
    if o not in meshes and o != rig:
        bpy.data.objects.remove(o, do_unlink=True)

def material(name, color_image, normal_image=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    surface = nodes.get('Principled BSDF')
    surface.inputs['Roughness'].default_value = 0.86
    if color_image:
        image = bpy.data.images.get(color_image)
        if image is None:
            raise RuntimeError('Missing source texture: ' + color_image)
        image.colorspace_settings.name = 'sRGB'
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = image
        mat.node_tree.links.new(tex.outputs['Color'], surface.inputs['Base Color'])
    if normal_image:
        image = bpy.data.images[normal_image]
        image.colorspace_settings.name = 'Non-Color'
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = image
        normal = nodes.new('ShaderNodeNormalMap')
        normal.inputs['Strength'].default_value = 0.8
        mat.node_tree.links.new(tex.outputs['Color'], normal.inputs['Color'])
        mat.node_tree.links.new(normal.outputs['Normal'], surface.inputs['Normal'])
    return mat

if role == 'reptile':
    body = bpy.data.objects['lizardman']
    skin = material('ReptileScalesPBR', 'diff2k+color.tga.jpg', 'normal.jpg')
    body.data.materials.clear()
    body.data.materials.append(skin)
    # Remove legacy IK/NLA control dependencies, retain all skin deform weights.
    rig.animation_data_clear()
    for bone in rig.pose.bones:
        for constraint in list(bone.constraints):
            bone.constraints.remove(constraint)
        bone.rotation_mode = 'XYZ'
        bone.rotation_euler = (0, 0, 0)
        bone.location = (0, 0, 0)
        bone.scale = (1, 1, 1)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    for i in range(5):
        bone = rig.data.edit_bones.new('SiegeTail%d' % i)
        bone.head = (0, 0.12 + i * .28, .65 - i * .10)
        bone.tail = (0, .40 + i * .28, .55 - i * .10)
        bone.parent = rig.data.edit_bones['pelvis' if i == 0 else 'SiegeTail%d' % (i-1)]
    bpy.ops.object.mode_set(mode='OBJECT')
    verts, faces = [], []
    rings, sides = 31, 16
    for i in range(rings):
        t = i / (rings - 1)
        radius = .145 * (1-t)**.85 + .002
        for j in range(sides):
            angle = j / sides * math.tau
            verts.append((radius*math.cos(angle), .12+t*1.48, .65-t*.5+radius*math.sin(angle)))
    for i in range(rings-1):
        for j in range(sides):
            a = i*sides+j
            b = i*sides+(j+1)%sides
            faces.append((a, b, b+sides, a+sides))
    faces += [tuple(reversed(range(sides))), tuple((rings-1)*sides+j for j in range(sides))]
    tail_mesh = bpy.data.meshes.new('MuscularTailMesh')
    tail_mesh.from_pydata(verts, [], faces)
    tail_mesh.update()
    tail = bpy.data.objects.new('MuscularTail', tail_mesh)
    bpy.context.collection.objects.link(tail)
    tail.parent = rig
    armor = material('DorsalKeratin', None)
    armor.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (.12,.17,.15,1)
    tail.data.materials.append(armor)
    modifier = tail.modifiers.new('TailSkin', 'ARMATURE')
    modifier.object = rig
    groups = [tail.vertex_groups.new(name='SiegeTail%d' % i) for i in range(5)]
    for i in range(rings):
        weight_pos = min(4.0, i/(rings-1)*4)
        lower = int(weight_pos)
        frac = weight_pos-lower
        ids = list(range(i*sides,(i+1)*sides))
        groups[lower].add(ids, 1-frac, 'REPLACE')
        if lower < 4:
            groups[lower+1].add(ids, frac, 'REPLACE')
    meshes.append(tail)
    # Broad curved scutes read as an armored dorsal silhouette from tank height.
    for i in range(9):
        on_tail = i >= 4
        y = .17 + max(0,i-3)*.23
        z = 1.40-i*.18 if not on_tail else .67-(i-3)*.085
        size = .22 if not on_tail else .19-(i-4)*.025
        vertices = [(-.035,y-.065,z),(.035,y-.065,z),(-.03,y+.07,z),(.03,y+.07,z),
                    (-.016,y+.065,z+size),(.016,y+.065,z+size),(0,y+.14,z+size*.48)]
        geom = bpy.data.meshes.new('ScuteMesh')
        geom.from_pydata(vertices, [], [(0,2,4),(1,5,3),(0,4,5,1),(2,3,6,4),(4,6,5),(3,5,6),(0,1,3,2)])
        fin = bpy.data.objects.new('DorsalScute%02d'%i, geom)
        bpy.context.collection.objects.link(fin)
        fin.parent = rig
        fin.data.materials.append(armor)
        bone_name = ('spine.03' if i < 2 else 'pelvis') if not on_tail else 'SiegeTail%d'%min(4,i-4)
        fin.vertex_groups.new(name=bone_name).add(list(range(len(vertices))),1.0,'REPLACE')
        modifier = fin.modifiers.new('ScuteSkin','ARMATURE')
        modifier.object = rig
        bevel = fin.modifiers.new('RoundedKeratin','BEVEL')
        bevel.width = .012
        bevel.segments = 2
        bpy.context.view_layer.objects.active = fin
        bpy.ops.object.modifier_apply(modifier=bevel.name)
        meshes.append(fin)
    # New 2-second cyclic stride: restrained limb swing, breathing and tail lag.
    for frame in range(1, 50, 2):
        phase = (frame-1)/48 * math.tau
        for bone in rig.pose.bones:
            name = bone.name
            bone.rotation_mode = 'XYZ'
            bone.rotation_euler = (0,0,0)
            if name in ('thigh.L','thigh.R'):
                bone.rotation_euler.x = math.sin(phase+(0 if name.endswith('.L') else math.pi))*.30
            elif name in ('shin.L','shin.R'):
                bone.rotation_euler.x = max(0,math.sin(phase+(0 if name.endswith('.L') else math.pi)))*.24
            elif name in ('upper_arm.L','upper_arm.R'):
                desired = Vector((.10 if bone.bone.head_local.x > 0 else -.10, -.20, -.97)).normalized()
                local_direction = bone.bone.matrix_local.to_3x3().inverted() @ desired
                bone.rotation_euler = Vector((0,1,0)).rotation_difference(local_direction).to_euler('XYZ')
                bone.rotation_euler.x += math.sin(phase+(math.pi if name.endswith('.L') else 0))*.12
            elif name.startswith('SiegeTail'):
                bone.rotation_euler.z = math.sin(phase-int(name[-1])*.55)*.09
            elif name == 'spine.02':
                bone.rotation_euler.y = math.sin(phase)*.04
            bone.keyframe_insert(data_path='rotation_euler',frame=frame)
    rig.animation_data.action.name = 'Walk'
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 49
    bpy.ops.object.select_all(action='DESELECT')
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    meshes = [body]
else:
    rig.animation_data_create()
    rig.animation_data.action = bpy.data.actions['Walk']
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = 40
    # Load the replacement CC0 bark from the updated archive, not a stale pack.
    bark = bpy.data.images.load(str(pathlib.Path(bpy.data.filepath).parent / 'texture/tree.png'))
    for obj in meshes:
        for index, old in enumerate(list(obj.data.materials)):
            name = old.name.lower()
            if 'tree' in name:
                obj.data.materials[index] = material('BarkPBR', bark.name, 'tree-norm.png')
            else:
                obj.data.materials[index] = material('StonePBR', 'forest-monster-skin1.png', 'forest-monster-norm.png')

for mesh in meshes:
    mesh.data.validate(clean_customdata=False)
    geometry = bmesh.new()
    geometry.from_mesh(mesh.data)
    bmesh.ops.recalc_face_normals(geometry, faces=list(geometry.faces))
    geometry.to_mesh(mesh.data)
    geometry.free()
    mesh.data.update()
    for polygon in mesh.data.polygons:
        polygon.use_smooth = True

bpy.context.scene.frame_set(bpy.context.scene.frame_start)
bpy.context.view_layer.update()
# Normalize all objects together, preserving skin bind matrices and animation.
points = [o.matrix_world @ Vector(corner) for o in meshes for corner in o.bound_box]
low = min(p.z for p in points)
high = max(p.z for p in points)
wrapper = bpy.data.objects.new('NormalizedCreature', None)
bpy.context.collection.objects.link(wrapper)
for obj in [rig] + meshes:
    if obj.parent is None:
        matrix = obj.matrix_world.copy()
        obj.parent = wrapper
        obj.matrix_world = matrix
wrapper.scale = (1/(high-low),)*3
wrapper.location.z = -low/(high-low)
# Blender -Y becomes glTF +Z: turn it to the game's -Z convention.
wrapper.rotation_euler.z = math.pi
bpy.ops.object.select_all(action='DESELECT')
for obj in [rig, wrapper] + meshes:
    obj.select_set(True)
pathlib.Path(output).parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(pathlib.Path(output).resolve()), export_format='GLB',
    use_selection=True, export_animations=True, export_animation_mode='ACTIVE_ACTIONS',
    export_frame_range=True, export_force_sampling=True, export_skins=True,
    export_rest_position_armature=True, export_image_format='AUTO')
# Blender labels merged active actions "Animation"; preserve the clip semantic.
path = pathlib.Path(output)
blob = path.read_bytes()
length = struct.unpack_from('<I', blob, 12)[0]
document = json.loads(blob[20:20+length])
assert len(document.get('animations', [])) == 1, 'Expected exactly one walk clip'
document['animations'][0]['name'] = 'Walk'
data = json.dumps(document, separators=(',', ':')).encode()
data += b' ' * (-len(data) % 4)
remainder = blob[20+length:]
path.write_bytes(struct.pack('<4sII', b'glTF', 2, 20+len(data)+len(remainder)) + struct.pack('<II',len(data),0x4E4F534A) + data + remainder)
print('SIEGE_BEAST_EXPORT',role,'source_height',high-low,'meshes',len(meshes),'output',output)
