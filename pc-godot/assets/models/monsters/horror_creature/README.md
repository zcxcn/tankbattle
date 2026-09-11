# Horror creature — endless siege

Source: [3D Horror Game Monster](https://opengameart.org/content/3d-horror-game-monster)
by **City Building Game Art / HorrorGameMaker.com**, published 2016-10-06.
License: **CC0 1.0**; publisher declaration checked 2026-09-11.

`horror_creature.glb` is converted from `Poses/Walk.fbx` in the publisher's
`Poses.zip`. The authored 70-bone skeleton, 3,584-triangle mesh and 38-frame
walk cycle are retained. Its 2K color and normal textures are used in game;
the legacy gloss-like roughness map is replaced by a physical scalar roughness
at runtime. The original map is retained in the GLB for provenance.

Only the creature and its images are exported. Maya editing controls and
Autodesk environment cube maps are excluded. The glTF uses four normalized
bone influences per vertex. Runtime instances share the source mesh and
archetype materials. Slow attack telegraphs, body falls and corpse fading are
original game code, not additional animation clips claimed from the source.

The body is approximately 1.86 meters high in the source walk pose. The game
presents three variants at 9, 12 and 16 meters, with independent health,
speed, skin coloration and reward values. There is no licensed anime character
or commercial franchise model in this asset.

Reproduce from the repository root:

```text
python scripts/pc048_import_monster.py
blender --background --python scripts/pc048_convert_monster.py -- work/pc048-monsters/Walk.fbx pc-godot/assets/models/monsters/horror_creature/horror_creature.glb
```

The downloader validates the official archive directory and checks HTTP ranges,
uncompressed file size, ZIP CRC-32 and the recorded FBX SHA-256. See
`provenance.json` for exact source-member and distribution-file hashes.
