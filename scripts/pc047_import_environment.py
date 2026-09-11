"""Fetch the pinned CC0 environment assets used by PC 0.4.7.

Powered by Poly Haven (https://polyhaven.com/).
Direct file URLs, lengths and publisher MD5 values were obtained from the
official public file API on 2026-09-11. Re-running does not query that API;
already valid files are reused. Only Python's standard library is required.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "pc-godot/assets/models/environment"
USER_AGENT = "Iron-Embers-Asset-Import/0.4.7 (https://github.com/zcxcn/tankbattle)"

# asset_id, directory, artist, entries: (relative path, URL, bytes, MD5)
ASSETS = (
    (
        "rock_09", "polyhaven_rock09", "Jenelle van Heerden",
        (
            ("rock_09_1k.gltf", "https://dl.polyhaven.org/file/ph-assets/Models/gltf/1k/rock_09/rock_09_1k.gltf", 2745, "d12ac6e8433fe1346fe6945154269f66"),
            ("rock_09.bin", "https://dl.polyhaven.org/file/ph-assets/Models/gltf/8k/rock_09/rock_09.bin", 286592, "6f2f71c9ca594566c1a3b29da27293a1"),
            ("textures/rock_09_arm_1k.jpg", "https://dl.polyhaven.org/file/ph-assets/Models/jpg/1k/rock_09/rock_09_arm_1k.jpg", 322950, "323d7cca17cd87656e7f80230a372368"),
            ("textures/rock_09_nor_gl_1k.jpg", "https://dl.polyhaven.org/file/ph-assets/Models/jpg/1k/rock_09/rock_09_nor_gl_1k.jpg", 757031, "dc1a208133a23006582f792a309c2dcc"),
            ("textures/rock_09_diff_1k.jpg", "https://dl.polyhaven.org/file/ph-assets/Models/jpg/1k/rock_09/rock_09_diff_1k.jpg", 595103, "07f92b23d6e05fbd28cbabecdd98b321"),
        ),
    ),
    (
        "concrete_tile_facade", "polyhaven_concrete_facade", "Charlotte Baglioni",
        (
            ("textures/concrete_tile_facade_diff_1k.jpg", "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/concrete_tile_facade/concrete_tile_facade_diff_1k.jpg", 625160, "73a90c8d921e477164100855aad21bc6"),
            ("textures/concrete_tile_facade_nor_gl_1k.jpg", "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/concrete_tile_facade/concrete_tile_facade_nor_gl_1k.jpg", 936569, "1433f810643d6bcbf50abdaf98fe9022"),
            ("textures/concrete_tile_facade_arm_1k.jpg", "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/concrete_tile_facade/concrete_tile_facade_arm_1k.jpg", 636755, "d123208761adb829b634024d1fe60fd9"),
        ),
    ),
    (
        "aerial_grass_rock", "polyhaven_aerial_grass", "Rob Tuytel",
        (
            ("textures/aerial_grass_rock_diff_1k.jpg", "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/aerial_grass_rock/aerial_grass_rock_diff_1k.jpg", 666655, "e920ce36afd0abff000b8366d3d768d3"),
            ("textures/aerial_grass_rock_nor_gl_1k.jpg", "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/aerial_grass_rock/aerial_grass_rock_nor_gl_1k.jpg", 904956, "c8aa4c4f09b113cc7edef89ddeaccad9"),
            ("textures/aerial_grass_rock_arm_1k.jpg", "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/aerial_grass_rock/aerial_grass_rock_arm_1k.jpg", 216829, "1f37fdb9b46b7fe34932ed9aa77df0bf"),
        ),
    ),
)


def valid(data: bytes, size: int, md5: str) -> bool:
    return len(data) == size and hashlib.md5(data).hexdigest() == md5


def main() -> None:
    total = 0
    for asset_id, folder, artist, entries in ASSETS:
        directory = DESTINATION / folder
        manifest = {
            "asset": asset_id,
            "artist": artist,
            "publisher": "Poly Haven",
            "powered_by": "https://polyhaven.com/",
            "source": f"https://polyhaven.com/a/{asset_id}",
            "file_api": f"https://api.polyhaven.com/files/{asset_id}",
            "license": "CC0-1.0",
            "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
            "license_confirmation": "https://polyhaven.com/license",
            "retrieved": "2026-09-11",
            "resolution": "1K",
            "files": [],
        }
        for name, url, size, md5 in entries:
            target = directory / name
            data = target.read_bytes() if target.exists() else b""
            if not valid(data, size, md5):
                request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
                with urllib.request.urlopen(request, timeout=90) as response:
                    data = response.read()
                if not valid(data, size, md5):
                    raise RuntimeError(f"Publisher checksum/length mismatch: {url}")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            total += len(data)
            record = {"path": name, "url": url, "size": size, "md5": md5,
                      "sha256": hashlib.sha256(data).hexdigest()}
            manifest["files"].append(record)
            print(f"Verified {folder}/{name}: {size:,} bytes", flush=True)
        (directory / "download-manifest.json").write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
        )
    print(f"Verified {total:,} bytes in {sum(len(asset[3]) for asset in ASSETS)} source files.", flush=True)


if __name__ == "__main__":
    main()
