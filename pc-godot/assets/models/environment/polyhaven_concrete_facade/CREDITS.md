# Concrete Tile Facade

Powered by [Poly Haven](https://polyhaven.com/).

- Artist: Charlotte Baglioni
- Original asset: https://polyhaven.com/a/concrete_tile_facade
- Download manifest API: https://api.polyhaven.com/files/concrete_tile_facade
- License: CC0 1.0 Universal, https://creativecommons.org/publicdomain/zero/1.0/
- Publisher license confirmation: https://polyhaven.com/license
- Retrieved and verified: 2026-09-11

The three original 1K PBR images are redistributed unchanged. Exact URLs,
lengths, publisher MD5 and SHA-256 checksums are in `download-manifest.json`.
Reproduce or verify with `scripts/pc047_import_environment.py`.
The Godot material is an Iron Embers integration of the original maps.

## Integration

Preload `res://assets/models/environment/polyhaven_concrete_facade/concrete_tile_facade.tres`
or use the diffuse, OpenGL normal and ARM maps in `textures/` directly.
ARM = R ambient occlusion, G roughness, B metallic. A complete texture repeat
covers approximately 2.1 metres. The supplied material uses world triplanar
mapping at 1/2.1 repeats per metre and normal strength 0.5 on modern concrete
facade panels, bridge piers and retaining walls. Duplicate it before changing
UV scales or tint for one surface. These are PBR surface textures;
building and bridge geometry is authored by the game.
