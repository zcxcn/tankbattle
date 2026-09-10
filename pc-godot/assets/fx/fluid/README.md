# Fluid simulation flipbooks

These images were authored in Houdini by Thomas ICHÉ / Unity Labs Paris and
released by Unity Technologies under **CC0 1.0**. This release is a standalone
CC0 image collection, not a Unity Asset Store package or engine restriction.

- Original release and explicit license:
  <https://unity.com/blog/engine-platform/free-vfx-image-sequences-flipbooks>
- License: <https://creativecommons.org/publicdomain/zero/1.0/>
- Original archives and SHA-256 checksums: `provenance.json` alongside this file.

The game uses lossless PNG conversions of Explosion00 (fire cooling into dark
smoke), Explosion01-nofire (rolling smoke), and Flame02 (small flame tongues).
The simulations are precomputed. Runtime shaders only interpolate adjacent
atlas frames and soften intersections with opaque scene geometry; they do
not simulate fluids or generate large textures on the CPU.

Reproduce the conversion with `scripts/import-fluid-vfx.py` after downloading
the archives named in `provenance.json` into `work/asset-downloads/unity-vfx`.
No network access is needed to build or play the game.
