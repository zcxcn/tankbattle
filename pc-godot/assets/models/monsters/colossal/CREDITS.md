# Colossal creatures — PC 0.4.10

## Glutton Demon

- Artist: **Teh_Bucket**. Concept: **RayMooHawk**, used with permission according to the artist.
- Original: https://opengameart.org/node/64952
- Download: https://opengameart.org/sites/default/files/glutton_final_0.blend
- License: **CC0 1.0 Universal**, https://creativecommons.org/publicdomain/zero/1.0/
- Source SHA-256: `c39c05059dfba8032dc8a8fbb6a6ec83d632ce88ee75a3578420467adb6c4979`.
- Adaptations: original mirror geometry baked, authored realistic diffuse and normal maps retained
  (not the alternative toon material), skinned Walk sampled, normalized feet/height/facing,
  physical material conversion and gameplay tint. Used as the 34m abyssal glutton.

## Rock Golem

- Original modeling: **hendori-sama**; rigging and UV improvements: **umask007**;
  retexture and animation: **Dm3d** for OpenDungeons.
- Original: https://opengameart.org/content/rock-golem
- Download: https://opengameart.org/sites/default/files/RockGolem.blend
- Selected license from the alternatives offered on the original upload:
  **Creative Commons Attribution 3.0 Unported**, https://creativecommons.org/licenses/by/3.0/
- Legal text: https://creativecommons.org/licenses/by/3.0/legalcode
- Source SHA-256: `6205d1a19ffaa97b4b3ba9e083590bf76ed1fb718f6a6e4b966b0e9f1371aa17`.
- Adaptations: editor floor and projectile prop removed; original mirrored stone body,
  packed color/normal maps, UVs, skin and sampled Walk retained; physical material conversion,
  normalized feet/height/facing and gameplay tints. The 52m golem and 72m juggernaut
  share this original mesh. No artist endorsement implied.

Reproduction: `scripts/convert-colossal-monsters.py`, Blender 5.2.1, with
`--background --disable-autoexec`. The game controls attack windup and collapse;
these are not physically simulated ragdolls. Two newly downloaded original models,
three gameplay roles; five original creature models and nine roles in total.
