# Aerial Grass Rock

Powered by [Poly Haven](https://polyhaven.com/).

- Artist: Rob Tuytel
- Original asset: https://polyhaven.com/a/aerial_grass_rock
- Download manifest API: https://api.polyhaven.com/files/aerial_grass_rock
- License: CC0 1.0 Universal, https://creativecommons.org/publicdomain/zero/1.0/
- Publisher license confirmation: https://polyhaven.com/license
- Retrieved and verified: 2026-09-11

The three original 1K PBR images are redistributed unchanged. Exact URLs,
lengths, publisher MD5 and SHA-256 checksums are in `download-manifest.json`.
Reproduce or verify with `scripts/pc047_import_environment.py`.
The Godot material is an Iron Embers integration of the original maps.

## Integration

This is a photographed natural grass, moss, stone and dirt surface. A full
texture repeat covers approximately 15 metres. For terrain, use the `diff`,
`nor_gl` and `arm` files under `textures/` in a slope-blended shader. ARM =
R ambient occlusion, G roughness, B metallic. The normal map is OpenGL.
`aerial_grass_rock.tres` is also provided for ordinary UV-mapped surfaces.
