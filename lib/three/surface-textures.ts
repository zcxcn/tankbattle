import { Texture, type PBRMaterial, type Scene } from './babylon';
import armorColor from '../../web/assets/generated/armor-painted-v1.webp?url';
import asphaltColor from '../../web/assets/generated/asphalt-v1.webp?url';
import brickColor from '../../web/assets/generated/brick-wall-v1.webp?url';
import concreteColor from '../../web/assets/surfaces/concrete-color.webp?url';
import concreteNormal from '../../web/assets/surfaces/concrete-normal.webp?url';
import concreteRoughness from '../../web/assets/surfaces/concrete-roughness.webp?url';
import metalColor from '../../web/assets/surfaces/painted-metal-color.webp?url';
import metalNormal from '../../web/assets/surfaces/painted-metal-normal.webp?url';
import metalRoughness from '../../web/assets/surfaces/painted-metal-roughness.webp?url';
import soilColor from '../../web/assets/surfaces/soil-color.webp?url';
import soilNormal from '../../web/assets/surfaces/soil-normal.webp?url';
import soilRoughness from '../../web/assets/surfaces/soil-roughness.webp?url';
import barkColor from '../../web/assets/surfaces/bark-color.webp?url';
import barkNormal from '../../web/assets/surfaces/bark-normal.webp?url';
import barkRoughness from '../../web/assets/surfaces/bark-roughness.webp?url';

export type SurfacePreset =
  | 'armor'
  | 'asphalt'
  | 'concrete'
  | 'brick'
  | 'paintedMetal'
  | 'roof'
  | 'soil'
  | 'bark'
  | 'rock';

type SurfaceOptions = { repeat?: number; mobile?: boolean; strength?: number };
type SurfaceTextures = {
  color: Texture;
  normal: Texture | null;
  roughness: Texture | null;
};
const sources = {
  // These generated albedos have no matching relief maps. Keep the material's
  // scalar roughness instead of projecting unrelated scanned cracks/mortar.
  armor: [armorColor, null, null],
  asphalt: [asphaltColor, null, null],
  concrete: [concreteColor, concreteNormal, concreteRoughness],
  brick: [brickColor, null, null],
  paintedMetal: [metalColor, metalNormal, metalRoughness],
  soil: [soilColor, soilNormal, soilRoughness],
  bark: [barkColor, barkNormal, barkRoughness],
} as const;
const scenes = new WeakMap<Scene, Map<string, SurfaceTextures>>();

/** Add surface detail while retaining the caller's paint/tint.
 * Call only when assets are enabled. These imports belong to the web entry graph;
 * the frozen Android entry never imports or copies this directory.
 */
export function applySurface(
  material: PBRMaterial,
  scene: Scene,
  preset: SurfacePreset,
  { repeat = 1, mobile = false, strength = 0.55 }: SurfaceOptions = {},
) {
  const source =
    preset === 'roof'
      ? 'paintedMetal'
      : preset === 'rock'
        ? 'concrete'
        : preset;
  const tiling = Math.max(0.05, Number.isFinite(repeat) ? repeat : 1);
  const [color, normal, roughness] = sources[source];
  const normalStrength = normal
    ? Math.max(0, Math.min(2, Number.isFinite(strength) ? strength : 0.55))
    : 0;
  const key = `${source}:${tiling}:${mobile}:${normalStrength}`;
  let cache = scenes.get(scene);
  if (!cache) {
    cache = new Map();
    scenes.set(scene, cache);
    const ownedCache = cache;
    scene.onDisposeObservable.addOnce(() => {
      ownedCache.clear();
      scenes.delete(scene);
    });
  }
  let textures = cache.get(key);
  if (!textures) {
    const make = (url: string, channel: string, gammaSpace: boolean) => {
      const texture = new Texture(
        url,
        scene,
        false,
        true,
        Texture.TRILINEAR_SAMPLINGMODE,
      );
      texture.name = `surface-${source}-${channel}-${tiling}`;
      texture.gammaSpace = gammaSpace;
      texture.uScale = texture.vScale = tiling;
      texture.wrapU = texture.wrapV = Texture.WRAP_ADDRESSMODE;
      texture.anisotropicFilteringLevel = mobile ? 2 : 8;
      return texture;
    };
    textures = {
      color: make(color, 'color', true),
      normal: normal ? make(normal, 'normal', false) : null,
      roughness: roughness ? make(roughness, 'roughness', false) : null,
    };
    if (textures.normal)
      textures.normal.level = normalStrength * (mobile ? 0.8 : 1);
    cache.set(key, textures);
  }
  material.albedoTexture = textures.color;
  material.bumpTexture = textures.normal;
  // Scanned normals are OpenGL (+Y); Babylon PBR uses DirectX tangent normals.
  material.invertNormalMapX = false;
  material.invertNormalMapY = !!textures.normal;
  material.metallicTexture = textures.roughness;
  material.useRoughnessFromMetallicTextureAlpha = false;
  material.useRoughnessFromMetallicTextureGreen = !!textures.roughness;
  material.useMetallnessFromMetallicTextureBlue = false;
  material.useAmbientOcclusionFromMetallicTextureRed = false;
  return material;
}
