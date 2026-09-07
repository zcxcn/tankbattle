# Third-party assets

The PC edition includes the following 1K PBR texture maps from
[Poly Haven](https://polyhaven.com/). Poly Haven publishes these assets under
the [CC0 license](https://polyhaven.com/license). Attribution is not required;
the sources and checksums are recorded here for provenance and repeatable
verification.

## Asphalt 01

Source: <https://polyhaven.com/a/asphalt_01>

| File | Map | MD5 |
| --- | --- | --- |
| `asphalt_01_diff_1k.jpg` | Diffuse | `43c88946c38109d77a24456686a376f9` |
| `asphalt_01_nor_gl_1k.jpg` | OpenGL normal | `ff3e4a0fc157cfa014fbcac68e662c38` |
| `asphalt_01_rough_1k.jpg` | Roughness | `92ffad35bc543f59ffd9860c53a98214` |

## Rough Concrete

Source: <https://polyhaven.com/a/rough_concrete>

| File | Map | MD5 |
| --- | --- | --- |
| `rough_concrete_diff_1k.jpg` | Diffuse | `82909f2db1e0453500703ae54e806f5c` |
| `rough_concrete_nor_gl_1k.jpg` | OpenGL normal | `61f785d44cdbf0b9f3bc68e471177358` |
| `rough_concrete_rough_1k.jpg` | Roughness | `4b530c64e200c3190f527ccc04a4c919` |

## Recorded combat audio

Both recordings are distributed under CC0. They are layered with the game's
original procedural transients and trimmed at playback time so one trigger
always produces one shot or blast.

| File | Source | Creator | SHA-256 |
| --- | --- | --- | --- |
| `tank_shots_preview_hq.mp3` | [Tank Shots](https://freesound.org/people/qubodup/sounds/239135/) | qubodup | `1f1a4224804266e92425239491ee56984ecf38edfa7a9f290cc458671204e9e5` |
| `muffled_distant_explosion.wav` | [Muffled Distant Explosion](https://opengameart.org/content/muffled-distant-explosion) | NenadSimic | `13a0bf75af94ec6d332bc71cba489b573466e05c4b17288158b3d683b41de39f` |

## Animated Tanks Pack

Four armored vehicle models are adapted from Quaternius' [Animated Tanks
Pack](https://quaternius.com/packs/animatedtanks.html). The official page and
the included `LICENSE.txt` dedicate the pack to the public domain under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). The models were
downloaded from the author's public Google Drive folder on 2026-09-07. The
original FBX files were converted to binary glTF with Godot 4.7.2's
`GLTFDocument`, without changing their geometry, armature, materials or
animations. Only the game-ready GLB derivatives are distributed with the
project.

| Asset | Original FBX SHA-256 | Distributed GLB SHA-256 |
| --- | --- | --- |
| `Tank.glb` | `9fcbecac34d1bcc586a815d92bb3b29b0affbdd66658f264dd13f0c19156134b` | `3fc2339d018213d71412538de7bf302ed119ba74d384d28d87656d4432c9855e` |
| `Tank2.glb` | `234fc762901b93f2babbbe07c24e7a5400cae4177df2da88bafae49780464fe7` | `f4d5ab0f7c6c91622f09bc0bdb0540b35dce2956f899b869b98201701b905678` |
| `Tank3.glb` | `79db2e3a79fa5b4d2e42749ff4f38a2921c8f85c5d63c9c284c480e27d0ee629` | `2e7e283284f888e3ea5c66a13e87c91832bfbcd95dbe377f56be29d6db5a4079` |
| `Tank4.glb` | `e34fbe21e8b23a0ee73ac6c5e5fab05ebae1894032cfc17db1e11c8a289d112f` | `b069691ef4b6a3f87e7bddee3bd997709ba23ab88e0773fae86c59ba25e0b363` |
