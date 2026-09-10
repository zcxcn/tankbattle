"""Build original, reusable glTF ordnance meshes in metres; no external assets.

Forward is -Z. The lathed ogive is authored as a smooth solid surface, with
separate copper driving bands, fuze, fins and an inset rocket exhaust nozzle.
Only fired projectiles are shown: there are no cartridge cases on flying rounds.
"""
from pathlib import Path
import json
import math
import struct

ROOT = Path(__file__).resolve().parents[1] / "assets" / "models" / "ordnance"
ROOT.mkdir(parents=True, exist_ok=True)
MATERIALS = [
    ("BlackenedSteel", [0.19, 0.21, 0.19, 1], .85, .34),
    ("CopperDrivingBand", [.64, .31, .12, 1], .82, .27),
    ("OliveHEPaint", [.21, .25, .095, 1], .3, .65),
    ("MachinedFuze", [.49, .51, .48, 1], .9, .25),
    ("YellowIdentification", [.82, .59, .07, 1], .15, .56),
    ("ExhaustInterior", [.027, .025, .022, 1], .65, .81),
]


def lathe(profile, segments=40):
    vertices, normals, indices = [], [], []
    for i, (z, radius) in enumerate(profile):
        prev = profile[max(0, i - 1)]
        nxt = profile[min(len(profile) - 1, i + 1)]
        dz, dr = nxt[0] - prev[0], nxt[1] - prev[1]
        nlength = math.hypot(dz, dr) or 1
        for j in range(segments):
            angle = 2 * math.pi * j / segments
            c, s = math.cos(angle), math.sin(angle)
            vertices.extend((radius * c, radius * s, z))
            normals.extend((abs(dz) * c / nlength, abs(dz) * s / nlength, -dr / nlength))
    for i in range(len(profile) - 1):
        for j in range(segments):
            a, b = i * segments + j, i * segments + (j + 1) % segments
            indices.extend((a, b, a + segments, b, b + segments, a + segments))
    return vertices, normals, indices


def fin(z0, z1, radius, reach, angle):
    # Swept, bevel-tipped stabilizer with two real faces and a closed edge.
    raw = [(radius, -.004, z0), (radius + reach, -.004, z0 + .08),
           (radius + reach * .85, -.004, z1), (radius, -.004, z1),
           (radius, .004, z0), (radius + reach, .004, z0 + .08),
           (radius + reach * .85, .004, z1), (radius, .004, z1)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
             (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    verts, normals, indices = [], [], []
    for face in faces:
        points = [raw[i] for i in face]
        a, b, c = points[:3]
        u, v = [b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)]
        n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
        length = math.sqrt(sum(x * x for x in n)) or 1
        n = [x / length for x in n]
        base = len(verts) // 3
        for x, y, z in points:
            verts.extend((x * math.cos(angle) - y * math.sin(angle), x * math.sin(angle) + y * math.cos(angle), z))
            normals.extend((n[0] * math.cos(angle) - n[1] * math.sin(angle), n[0] * math.sin(angle) + n[1] * math.cos(angle), n[2]))
        indices.extend((base, base + 1, base + 2, base, base + 2, base + 3))
    return verts, normals, indices


def save(name, parts):
    blob = bytearray()
    gltf = {"asset": {"version": "2.0", "generator": "Iron Embers original ordnance authoring"},
            "scene": 0, "scenes": [{"nodes": list(range(len(parts)))}], "nodes": [], "meshes": [],
            "buffers": [], "bufferViews": [], "accessors": [],
            "materials": [{"name": label, "pbrMetallicRoughness": {"baseColorFactor": color, "metallicFactor": metal, "roughnessFactor": rough}} for label, color, metal, rough in MATERIALS]}
    def accessor(values, code, dimensions, kind, target):
        while len(blob) % 4:
            blob.append(0)
        offset = len(blob)
        blob.extend(struct.pack("<" + code * len(values), *values))
        view = len(gltf["bufferViews"])
        gltf["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(blob) - offset, "target": target})
        entry = {"bufferView": view, "componentType": 5126 if code == "f" else 5125, "count": len(values) // dimensions, "type": kind}
        if kind == "VEC3":
            entry["min"] = [min(values[i::3]) for i in range(3)]
            entry["max"] = [max(values[i::3]) for i in range(3)]
        gltf["accessors"].append(entry)
        return len(gltf["accessors"]) - 1
    for label, material, geometry in parts:
        positions, normals, indices = geometry
        primitive = {"attributes": {"POSITION": accessor(positions, "f", 3, "VEC3", 34962), "NORMAL": accessor(normals, "f", 3, "VEC3", 34962)}, "indices": accessor(indices, "I", 1, "SCALAR", 34963), "material": material}
        index = len(gltf["meshes"])
        gltf["meshes"].append({"name": label, "primitives": [primitive]})
        gltf["nodes"].append({"name": label, "mesh": index})
    gltf["buffers"] = [{"byteLength": len(blob)}]
    document = json.dumps(gltf, separators=(",", ":")).encode()
    document += b" " * ((-len(document)) % 4)
    blob += b"\0" * ((-len(blob)) % 4)
    result = struct.pack("<III", 0x46546C67, 2, 28 + len(document) + len(blob))
    result += struct.pack("<II", len(document), 0x4E4F534A) + document
    result += struct.pack("<II", len(blob), 0x004E4942) + blob
    (ROOT / f"{name}.glb").write_bytes(result)
    print(name, len(result), "bytes", sum(len(p[2][2]) // 3 for p in parts), "triangles")


def band(z, radius, width):
    return lathe([(z, radius - .004), (z + .003, radius), (z + width - .003, radius), (z + width, radius - .004)])


save("ap_shell", [
    ("OgivePenetrator", 0, lathe([(-.40, .001), (-.37, .008), (-.33, .020), (-.27, .038), (-.20, .052), (-.12, .059), (.18, .059), (.25, .045), (.25, 0)])),
    ("CopperBandForward", 1, band(.105, .064, .025)),
    ("CopperBandRear", 1, band(.15, .064, .022)),
    ("MachinedBase", 3, lathe([(.24, .044), (.256, .040), (.26, 0)])),
])
save("he_shell", [
    ("OliveExplosiveBody", 2, lathe([(-.285, .018), (-.25, .030), (-.205, .046), (-.135, .059), (.18, .059), (.23, .045), (.23, 0)])),
    ("ImpactFuze", 3, lathe([(-.35, .005), (-.335, .011), (-.3, .017), (-.28, .017)])),
    ("CopperDrivingBand", 1, band(.145, .065, .035)),
    ("YellowHEBand", 4, band(-.11, .061, .017)),
])
save("machine_gun_bullet", [
    ("CopperJacketOgive", 1, lathe([(-.035, .0001), (-.032, .0012), (-.025, .0033), (-.012, .00635), (.011, .00635), (.020, .0048), (.020, 0)], 24)),
    ("CrimpGroove", 0, band(.003, .0066, .005)),
])
rocket_parts = [
    ("ShapedChargeOgive", 2, lathe([(-.62, .001), (-.58, .018), (-.52, .047), (-.44, .069), (-.25, .069), (-.18, .052), (.40, .052), (.46, .045)])),
    ("WarheadBand", 4, band(-.36, .071, .021)),
    ("MotorSteelBand", 3, band(.27, .056, .036)),
    ("ExhaustNozzle", 0, lathe([(.39, .051), (.46, .045), (.49, .043), (.49, .031), (.42, .024)])),
    ("NozzleInterior", 5, lathe([(.415, .024), (.416, 0)])),
]
for i in range(4):
    rocket_parts.append((f"StabilizerFin{i + 1}", 0, fin(.17, .46, .047, .105, i * math.pi / 2)))
save("rocket", rocket_parts)
