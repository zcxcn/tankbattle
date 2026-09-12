# Woodland tree — Tree Small 02

Powered by [Poly Haven](https://polyhaven.com/).

- Artist: **Rico Cilliers**.
- Original asset: https://polyhaven.com/a/tree_small_02
- Official file manifest: https://api.polyhaven.com/files/tree_small_02
- License: **CC0 1.0 Universal**, https://creativecommons.org/publicdomain/zero/1.0/
- Publisher confirmation: https://polyhaven.com/license
- Retrieved and verified: 2026-09-12.

`woodland_tree.glb` is adapted from the original 1K glTF. The branch/leaf geometry
is simplified for forest instancing, retaining the silhouette, UVs and PBR textures;
the origin is grounded and the source height normalized to 16 metres. Runtime
instances vary in scale and rotation and use alpha-scissor foliage and trunk collision.
The tree is rendered in spatial MultiMesh batches, not recreated from primitives.

`download-manifest.json` pins original URLs, byte lengths, publisher MD5 and verified
SHA-256. The large original glTF and binary are working inputs, not runtime dependencies.
To reproduce, download the manifest files into `work/asset-review/woodland/source/`,
then run Blender in background with `--python scripts/prepare-woodland-tree.py`.
`conversion.json` records original and final geometry counts.
