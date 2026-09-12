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

## Realistic armored vehicles

The PC edition uses three independently articulated, textured vehicle models.
All three are licensed under [Creative Commons Attribution 4.0
International](https://creativecommons.org/licenses/by/4.0/). The title screen
shows a compact credit and each model directory contains a distribution-ready
source and modification notice.

### Challenger 2 - Shooting Range

- Creator: [Tom Zimmermann (`tomm8`)](https://sketchfab.com/tomm8)
- Source: [Challenger 2 - Shooting Range](https://sketchfab.com/3d-models/challenger-2-shooting-range-e70234f6d695467499abc56646ab3e66)
- Changes: removed the shooting-range diorama; baked source transforms;
  converted to metric Godot +Y-up/-Z-forward coordinates; centered and grounded
  the tank; regrouped body, turret and gun geometry; added accurate articulation
  pivots and a muzzle locator. All 93,614 source triangles and the five original
  PBR material sets were retained.
- Distributed file: `realistic/challenger2/challenger2.glb`
- SHA-256: `dd2b79e777f4c234c15a45afe83f42a29bc2b4ade13fdf4558e0afc746bfa8b4`

### KF51 Panther

- Uploader and required credit: [GRIP420](https://sketchfab.com/GRIP420)
- Model and textures credited by the uploader to: [David Falke](https://sketchfab.com/davidfalke)
- Source: [KF51 Panther](https://sketchfab.com/3d-models/kf51-panther-505555987f33412e9f510642dbad7acb)
- Changes: baked source transforms; separated and classified connected parts;
  consolidated them into eight body/turret/gun meshes; converted to metric
  Godot coordinates; centered and grounded the tank; added articulation pivots
  and a muzzle locator. All 63,016 source triangles and four original PBR
  material sets were retained. The derivative is distributed only as part of
  this game, in line with the uploader's request not to resell the standalone
  model.
- Distributed file: `realistic/kf51/kf51_panther.glb`
- SHA-256: `fa68f18cdba3c4e0900b36e9e5ed6ae311a5f16e9bb9492911ff1bdc8c06732b`

### KV-2 heavy tank 1940

- Creator: [Comrade1280](https://sketchfab.com/comrade1280)
- Source: [KV-2 heavy tank 1940](https://sketchfab.com/3d-models/kv-2-heavy-tank-1940-ba8b84d78c0a42038cf2eaa4210ef296)
- Changes: removed the display floor; converted to metric Godot coordinates;
  centered and grounded the tank; separated the body, wheels, tracks, turret and
  gun; added articulation pivots and a muzzle locator; reduced 583,381 source
  triangles to 176,035 and resized 4K maps to 2K. The four original PBR material
  sets, including base color, metal/roughness, normal and ambient occlusion, are
  retained.
- Distributed file: `realistic/kv2/kv2_boss.glb`
- SHA-256: `068299074352f4738521ca50869dc5bf10e7160ecc6a65721a06bce810bb13de`

## Expanded PC weapon and impact recordings

The PC edition now includes locally packaged single-shot cannon variants,
machine-gun, rocket, armored impact and explosion clips. They were copied from
the existing licensed web audio pack without changing the web or Android builds.
Full source links and edits: [PC combat recording credits](audio/combat/README.md).
Per-file checksums and source processing: [provenance](audio/combat/provenance.json).

Required machine-gun attribution: **KuraiWolf / Nightshade Game Studios**,
[Light Machine Gun](https://opengameart.org/content/light-machine-gun),
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), trimmed and mastered.
The remaining added clips use CC0 or public-domain sources documented above.

## Factory buildings and modular architecture

The PC 0.4.0 districts use the actual modeled brick panels, recessed windows,
frames, steel doors, loading shutters and cornices from **Modular Factory
Facade**, by **James Ray Cock / Poly Haven**, published under CC0 1.0.
[Original model](https://polyhaven.com/a/modular_factory_facade).
The original binary and 1K PBR images are retained and verified against the
publisher's download manifest. Source geometry is shared in MultiMesh batches,
with generated LODs and a 175m detail cutoff. The seven assembled building
classes add game-authored roofs, balconies, transformers, chimneys and fittings.
[Source, license and modifications](models/environment/polyhaven_factory/CREDITS.md).

## Battlefield music, radio and vehicle motion

Three original synthesized combat scores and thirteen English actor recordings
are packaged for offline playback. The CC0 Kenney Voiceover Pack features
Jeffrey M. Smith and Giselle; Chinese subtitles translate their actual words.
Four additional status notifications use text and an interface cue where no
matching recorded line exists. Vehicle motion combines an actual tank-engine
recording and mechanical tread/steering foley.

Required attribution: **qubodup, Tank Engine Loop.flac**,
[Freesound source](https://freesound.org/people/qubodup/sounds/200303/),
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), processed and looped.
**77Pacer, Tank Tread**,
[Freesound source](https://freesound.org/people/77Pacer/sounds/425271/), CC0,
supplies mechanical foley for the tread and steering layers.
[Complete audio attribution and processing](audio/battlefield/README.md),
[per-file hashes and quality measurements](audio/battlefield/provenance.json).

## Fluid explosion, smoke and flame animation

Houdini simulation sequences by **Unity Labs Paris / Unity Technologies**, released
by Thomas Iché under **CC0 1.0**, supply the animated fire and smoke textures.
[Original publication and downloads](https://unity.com/blog/engine-platform/free-vfx-image-sequences-flipbooks).
The PC renderer uses adapted texture sheets inside Godot; the engine is unchanged.
[Source archives, license and processing](fx/fluid/README.md),
[asset checksums](fx/fluid/provenance.json).

## PC 0.4.7 city and river landscape

Three additional CC0 resources from **Poly Haven** are packaged offline. The
11 original payload files total 5,951,345 bytes; publisher MD5, size and SHA-256
are recorded in each directory's download manifest.

- **Rock 09**, Jenelle van Heerden: [original scanned model](https://polyhaven.com/a/rock_09).
  The original glTF and 1K PBR maps are retained. A scene wrapper grounds,
  centers and scales the model for shared riverbank placements.
  [Source and license](models/environment/polyhaven_rock09/CREDITS.md).
- **Concrete Tile Facade**, Charlotte Baglioni: [original surface](https://polyhaven.com/a/concrete_tile_facade).
  Original 1K color, normal and ARM maps dress game-authored stepped towers.
  [Source and license](models/environment/polyhaven_concrete_facade/CREDITS.md).
- **Aerial Grass Rock**, Rob Tuytel: [original surface](https://polyhaven.com/a/aerial_grass_rock).
  Original 1K color, normal and ARM maps are blended across continuous hills.
  [Source and license](models/environment/polyhaven_aerial_grass/CREDITS.md).

The tower geometry, engineered bridges, river shader and hill heightfields are
original game code. They are not downloaded landmark replicas and are not
attributed to the above artists. Reproduction and checksum verification:
`scripts/pc047_import_environment.py`.

## PC 0.4.8 endless horror creature

**3D Horror Game Monster**, published by City Building Game Art / HorrorGameMaker.com,
is a CC0 1.0 skinned creature from [the original artist upload](https://opengameart.org/content/3d-horror-game-monster).
The game retains its 3,584-triangle mesh, 70-bone rig, authored Walk animation and
2K color/normal skin textures. Three gameplay variants use 9, 12 and 16 metre bodies;
attack poses, accelerated falling and corpse fading are implemented in Godot.
These variants share one original creature model. Source archive member hashes,
conversion details and the source dedication are included in
[monster credits](models/monsters/horror_creature/CREDITS.md) and
[provenance](models/monsters/horror_creature/provenance.json).

## PC 0.4.9 additional siege creatures

Two additional authored meshes join the horror creature: CDmir/TinyWorlds'
CC0 Forest Monster, and thecubber's CC BY 3.0 Reptile commissioned by the
[OpenGameArt.org community](https://opengameart.org).
The reptile is adapted with a skinned tail, dorsal scutes and a new walk animation.
Source links, licenses and modification notes: [siege beast credits](models/monsters/siege_beasts/CREDITS.md).

## PC 0.4.10 colossal creatures

Teh_Bucket / RayMooHawk's **Glutton Demon** (CC0) and
hendori-sama / umask007 / Dm3d's **Rock Golem** (selected CC BY 3.0) add two
authored skinned models with original color and normal maps. The glutton is 34m;
the stone body is shared by 52m and 72m gameplay roles.
[Source links, checksums, licenses and adaptations](models/monsters/colossal/CREDITS.md).

## PC 0.4.13 woodland

Rico Cilliers' **Tree Small 02** from Poly Haven (CC0) supplies the textured trees
in Qinglan Valley. Original UV/PBR textures accompany a normalized, simplified
mesh for spatial forest instancing. [Source, license and conversion details](models/environment/polyhaven_tree_small02/CREDITS.md).

## Original modeled ordnance

AP shells, HE shells, machine-gun bullets and rockets are original closed GLB
geometry generated for this game. They use curved noses, driving bands, fuzes
and fins as appropriate. [Generator, sizes and CC0 license](models/ordnance/README.md).
