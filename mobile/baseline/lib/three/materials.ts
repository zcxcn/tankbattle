import { assetUrl } from '../asset-url';
import {
  Color3,
  PBRMaterial,
  Scene,
  StandardMaterial,
  Texture,
} from './babylon';
export type Quality = 'cinematic' | 'balanced' | 'performance';
export function pbr(
  scene: Scene,
  name: string,
  color: string,
  metallic = 0,
  roughness = 0.8,
) {
  const m = new PBRMaterial(name, scene);
  m.albedoColor = Color3.FromHexString(color);
  m.metallic = metallic;
  m.roughness = roughness;
  m.environmentIntensity = 0.55;
  return m;
}
export function emissive(
  scene: Scene,
  name: string,
  color: string,
  strength = 1,
) {
  const m = new StandardMaterial(name, scene);
  m.diffuseColor = Color3.Black();
  m.emissiveColor = Color3.FromHexString(color).scale(strength);
  m.disableLighting = true;
  return m;
}
export function createMaterials(scene: Scene, assets = true, mobile = false) {
  const armor = pbr(scene, 'olive-composite-armor', '#919a73', 0.52, 0.46),
    enemy = pbr(scene, 'scorched-enemy-armor', '#937c69', 0.56, 0.5),
    heavy = pbr(scene, 'siege-armor', '#544d44', 0.7, 0.42),
    steel = pbr(scene, 'blackened-steel', '#3b4140', 0.84, 0.36),
    rubber = pbr(scene, 'track-rubber', '#171a18', 0.06, 0.95),
    edges = pbr(scene, 'edge-wear-metal', '#afb0a0', 0.78, 0.32),
    ground = pbr(scene, 'rain-soaked-concrete', '#93958a', 0.12, 0.74),
    concrete = pbr(scene, 'old-concrete', '#7c796d', 0.02, 0.9),
    brick = pbr(scene, 'exposed-brick', '#86715a', 0.02, 0.94),
    glass = pbr(scene, 'optical-glass', '#1a3937', 0.75, 0.16);
  if (assets) {
    const at = new Texture(
      assetUrl(mobile ? '/mobile/armor.webp' : '/armor-texture.png'),
      scene,
    );
    at.uScale = 1.5;
    at.vScale = 1.5;
    at.anisotropicFilteringLevel = mobile ? 2 : 8;
    armor.albedoTexture = at;
    enemy.albedoTexture = at;
    heavy.albedoTexture = at;
    const gt = new Texture(
      assetUrl(mobile ? '/mobile/ground.webp' : '/ground-texture.png'),
      scene,
    );
    gt.uScale = 20;
    gt.vScale = 20;
    gt.anisotropicFilteringLevel = mobile ? 2 : 8;
    ground.albedoTexture = gt;
  }
  const lamp = emissive(scene, 'warm-headlights', '#ffdfad', 2.4),
    red = emissive(scene, 'enemy-optics', '#ff744a', 1.8),
    blue = emissive(scene, 'energy-blue', '#7fcbd3', 1.6),
    ember = emissive(scene, 'molten-fire', '#ff9c39', 2.4),
    white = emissive(scene, 'tracer-core', '#fff1b0', 2.8),
    marking = pbr(scene, 'faded-marking', '#ddd9b4', 0.05, 0.8);
  return {
    armor,
    enemy,
    heavy,
    steel,
    rubber,
    edges,
    ground,
    concrete,
    brick,
    glass,
    lamp,
    red,
    blue,
    ember,
    white,
    marking,
  };
}
export type Materials = ReturnType<typeof createMaterials>;
