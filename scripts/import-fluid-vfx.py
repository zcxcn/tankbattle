"""Convert the original CC0 Unity Labs TGA flipbooks to lossless runtime PNGs.

Source zip files stay in work/asset-downloads/unity-vfx. No downloading occurs
at build or at runtime. Source and output hashes are written for verification.
"""
import hashlib
import io
import json
from pathlib import Path
import zipfile
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "work/asset-downloads/unity-vfx"
TARGET = ROOT / "pc-godot/assets/fx/fluid"
TARGET.mkdir(parents=True, exist_ok=True)
records = []
for source, output in [("Explosion00", "explosion"), ("Explosion01-nofire", "smoke"), ("Flame02", "flame")]:
    archive = SOURCE / f"{source}-flipbooks.zip"
    with zipfile.ZipFile(archive) as package:
        member = next(name for name in package.namelist() if name.lower().endswith(".tga"))
        raw = package.read(member)
    image = Image.open(io.BytesIO(raw)).convert("RGBA")
    destination = TARGET / f"{output}.png"
    image.save(destination, optimize=True)
    records.append({"file": destination.name, "dimensions": list(image.size), "source_member": member,
                    "source": f"https://unity3d.com/files/labs/downloads/vfx/assets01/{source}/{source}-flipbooks.zip",
                    "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                    "source_tga_sha256": hashlib.sha256(raw).hexdigest(),
                    "sha256": hashlib.sha256(destination.read_bytes()).hexdigest(), "license": "CC0-1.0"})
(TARGET / "provenance.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")
print(json.dumps(records, indent=2))
