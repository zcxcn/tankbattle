"""Run with Blender --background --python this.py -- Walk.fbx output.glb.

Converts the CC0 HorrorGameMaker creature and its authored walk animation.
Only the deform skeleton, skin mesh and four PBR image maps are exported;
Maya editor controls and Autodesk environment cube maps are excluded.
"""
import json
import pathlib
import sys
import struct

import bpy

args = sys.argv[sys.argv.index("--") + 1 :]
source, destination = map(lambda s: pathlib.Path(s).resolve(), args[:2])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(source))
mesh = bpy.data.objects["Creature1"]
rig = mesh.modifiers[0].object
action = rig.animation_data.action
action.name = "Walk"
for obj in list(bpy.data.objects):
    if obj not in (mesh, rig):
        bpy.data.objects.remove(obj, do_unlink=True)
rig.name = "HorrorCreatureRig"
mesh.name = "HorrorCreatureSkin"
mat = mesh.data.materials[0]
mat.name = "NecroticSkinPBR"
mat.use_nodes = True
nodes = mat.node_tree.nodes
nodes.clear()
out = nodes.new("ShaderNodeOutputMaterial")
surface = nodes.new("ShaderNodeBsdfPrincipled")
surface.inputs["Metallic"].default_value = 0.0
surface.inputs["Roughness"].default_value = 0.82
mat.node_tree.links.new(surface.outputs["BSDF"], out.inputs["Surface"])
for image_name, channel in [("file4", "Base Color"), ("file5", "Normal"), ("file7", "Roughness")]:
    image = bpy.data.images[image_name]
    image.name = {"file4": "CreatureAlbedo", "file5": "CreatureNormal", "file7": "CreatureRoughness"}[image_name]
    image.colorspace_settings.name = "sRGB" if channel == "Base Color" else "Non-Color"
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    if channel == "Normal":
        normal = nodes.new("ShaderNodeNormalMap")
        normal.inputs["Strength"].default_value = 0.8
        mat.node_tree.links.new(tex.outputs["Color"], normal.inputs["Color"])
        mat.node_tree.links.new(normal.outputs["Normal"], surface.inputs[channel])
    else:
        mat.node_tree.links.new(tex.outputs["Color"], surface.inputs[channel])
for polygon in mesh.data.polygons:
    polygon.use_smooth = True
bpy.context.scene.frame_start = 2
bpy.context.scene.frame_end = 40
bpy.context.scene.frame_set(2)
for obj in bpy.context.selected_objects:
    obj.select_set(False)
rig.select_set(True)
mesh.select_set(True)
bpy.context.view_layer.objects.active = rig
destination.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=str(destination), export_format="GLB", use_selection=True,
    export_animations=True, export_animation_mode="ACTIVE_ACTIONS",
    export_frame_range=True, export_force_sampling=True,
    export_current_frame=False, export_rest_position_armature=True,
    export_skins=True, export_image_format="AUTO",
)
# Blender merges active actions under a generic clip name. Preserve a stable
# semantic clip name without changing any of the authored motion samples.
blob = destination.read_bytes()
json_length = struct.unpack_from("<I", blob, 12)[0]
document = json.loads(blob[20 : 20 + json_length])
for animation in document.get("animations", []):
    animation["name"] = "Walk"
encoded = json.dumps(document, separators=(",", ":")).encode()
encoded += b" " * (-len(encoded) % 4)
binary_chunks = blob[20 + json_length :]
destination.write_bytes(struct.pack("<4sII", b"glTF", 2, 20 + len(encoded) + len(binary_chunks))
                        + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded + binary_chunks)
print(json.dumps({"output": str(destination), "vertices": len(mesh.data.vertices),
                  "triangles": sum(len(p.vertices) - 2 for p in mesh.data.polygons),
                  "bones": len(rig.data.bones), "animation": "Walk", "frames": [2, 40]}))
