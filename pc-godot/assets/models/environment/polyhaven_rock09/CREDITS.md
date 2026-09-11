# Rock 09

Powered by [Poly Haven](https://polyhaven.com/).

- Artist: Jenelle van Heerden
- Original asset: https://polyhaven.com/a/rock_09
- Download manifest API: https://api.polyhaven.com/files/rock_09
- License: CC0 1.0 Universal, https://creativecommons.org/publicdomain/zero/1.0/
- Publisher license confirmation: https://polyhaven.com/license
- Retrieved and verified: 2026-09-11

The original glTF, geometry and 1K PBR images are redistributed unchanged.
`download-manifest.json` records direct official download URLs, byte lengths,
the publisher's MD5 checksums and independently calculated SHA-256 checksums.
Reproduce or verify the download with `scripts/pc047_import_environment.py`.
The code-authored normalization wrapper is an Iron Embers addition.

## Integration

The scan is glTF Y-up with one mesh node, `rock_09_LOD0`, one material, 6,628
vertices and 12,416 triangles. Native bounds are approximately 0.074010 ×
0.032869 × 0.144625 metres (X × Y × Z). The source is a small scanned rock;
it must be scaled for landscape use.

Load `res://assets/models/environment/polyhaven_rock09/rock_09_normalized.tscn`
for a centered, ground-aligned rock with a 1 metre long Z axis, 0.512 metre
width and 0.227 metre height. Scale the root by 3–10 for riverbank outcrops.
Use moderate non-uniform scaling and rotation for variants. Its source mesh
and material can be extracted once for MultiMesh batching. Collision should
be provided by a simple fitted shape where the rock is reachable; this scene
contains visual geometry only.

The original material includes diffuse, OpenGL normal and roughness maps.
The packed ARM image stores AO in R, roughness in G and metallic in B.
