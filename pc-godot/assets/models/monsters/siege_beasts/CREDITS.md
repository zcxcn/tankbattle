# Siege beasts — PC 0.4.9

## Reptile / reaver / kaiju

Model by **thecubber**, commissioned by the **OpenGameArt.org community**
(https://opengameart.org).

- Original: https://opengameart.org/content/rigged-textured-reptile
- Download: https://opengameart.org/sites/default/files/raptile_rig_fin.blend_.7z
- Chosen license from the offered alternatives: **Creative Commons Attribution 3.0 Unported**.
- License: https://creativecommons.org/licenses/by/3.0/
- Legal text: https://creativecommons.org/licenses/by/3.0/legalcode
- Source archive SHA-256: `8201d9f9c3ad97597291c3a2e7aa2b2535e70b0460c23fee55f2acb76668a75c`.
- Adaptations: old Blender materials converted to PBR; original skin, UVs and 2K
  normal map retained; skinned muscular tail and rounded dorsal scutes added;
  new deterministic walk/tail animation, normalized units, gameplay tints.
- Reaver and kaiju share this adapted asset at 30m and 60m. It is a reptilian
  siege creature, not a licensed Godzilla character model. No endorsement implied.

## Forest monster

**CDmir**, with **TinyWorlds**, created for Kelgar (https://www.kelgar.org).

- Original: https://opengameart.org/content/forest-monster
- Download: https://opengameart.org/sites/default/files/forest-monster_0.7z
- License: **CC0 1.0 Universal**, https://creativecommons.org/publicdomain/zero/1.0/
- Source archive SHA-256: `3378edfe2441d1cee93feeeb6e045b9ff0c700d85b398dfa6c29c83f7e696a5e`.
- The author replaced the earlier noncommercial bark texture on 2015-09-03 and
  confirmed that the updated work is entirely CC0. The conversion explicitly uses
  `texture/tree.png` from that updated archive. Original publisher notes retained
  in Publisher-README.txt.
- Adaptations: editor control meshes removed; original body/tree rig, walk, UVs
  and texture/normal maps retained; material conversion and normalized units.

Conversion: `scripts/convert-siege-beasts.py`, Blender 5.2.1 with
`--background --disable-autoexec`. Downloaded .blend Python auto-execution is disabled.
Both models use actual skinned meshes and smooth normals. Attack/fall remains
game-controlled animation, not a physical ragdoll simulation.
