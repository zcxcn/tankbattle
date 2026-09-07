# Photographed web material surfaces

These local web assets use photographed PBR surface maps from [Poly Haven](https://polyhaven.com/textures), licensed under [CC0 1.0](https://polyhaven.com/license). The game serves its own compressed copies; it does not contact Poly Haven while playing.

| Game material | Original asset | Authors |
| --- | --- | --- |
| Roads | [Asphalt 01](https://polyhaven.com/a/asphalt_01) | Charlotte Baglioni (photography), Dario Barresi (processing) |
| Concrete / rubble | [Rough Concrete](https://polyhaven.com/a/rough_concrete) | Dimitrios Savva |
| Brick walls | [Red Brick 03](https://polyhaven.com/a/red_brick_03) | Rob Tuytel |
| Painted armor / metal roofing | [Rusty Metal 02](https://polyhaven.com/a/rusty_metal_02) | Rob Tuytel |
| Soil | [Forest Ground 04](https://polyhaven.com/a/forest_ground_04) | Rob Tuytel (photography, processing), Rico Cilliers (minor adjustment) |
| Tree bark | [Bark Brown 02](https://polyhaven.com/a/bark_brown_02) | Rob Tuytel |

`provenance.json` records the official download URLs, original checksums, output SHA-256 checksums, dimensions, and conversion details for every file. The original 1K JPEG map checksums were verified against Poly Haven's public asset API. Previously acquired asphalt and concrete maps were copied from the PC assets without changing those files.

Color and normal maps are 1024 × 1024; bark and roughness maps are 512 × 512. WebP compression reduces download cost. The painted metal color map is converted to neutral weathering so player/enemy paint remains readable. Normal and roughness channels are linear data, while color uses sRGB. OpenGL normal maps are converted in the material with `invertNormalMapY`, following [Babylon's normal map convention documentation](https://doc.babylonjs.com/features/featuresDeepDive/materials/using/normalMaps/).

These files are imported by the web renderer through Vite, which produces hashed asset URLs under the configured Pages base path. They are outside `public/` and the frozen Android dependency graph, so the Android package does not acquire these maps.
