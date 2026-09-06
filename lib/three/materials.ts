import { assetUrl } from '../asset-url';
import {
  Color3,
  PBRMaterial,
  Scene,
  StandardMaterial,
  Texture,
  RawTexture,
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
  const armor = pbr(scene, 'olive-composite-armor', '#727963', 0.18, 0.76),
    enemy = pbr(scene, 'scorched-enemy-armor', '#766454', 0.16, 0.8),
    heavy = pbr(scene, 'siege-armor', '#454743', 0.28, 0.69),
    steel = pbr(scene, 'blackened-steel', '#444943', 0.87, 0.49),
    rubber = pbr(scene, 'track-rubber', '#171a18', 0.06, 0.95),
    edges = pbr(scene, 'edge-wear-metal', '#91948b', 0.8, 0.5),
    mud = pbr(scene, 'dried-track-mud', '#514538', 0, 0.97),
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
    // Tileable micro-surface normals for cast armor and rolled steel. No new downloads.
    const size = 128,
      normal = new Uint8Array(size * size * 4);
    const height = (x: number, y: number) =>
      Math.sin((x * Math.PI) / 8) * Math.cos((y * Math.PI) / 4) * 0.08 +
      Math.sin((x * Math.PI) / 2 + Math.sin((y * Math.PI) / 16)) * 0.05;
    for (let y = 0; y < size; y++)
      for (let x = 0; x < size; x++) {
        const dx = height(x + 1, y) - height(x - 1, y),
          dy = height(x, y + 1) - height(x, y - 1);
        const len = Math.hypot(dx, dy, 1),
          i = (y * size + x) * 4;
        normal[i] = Math.round(128 - (dx / len) * 127);
        normal[i + 1] = Math.round(128 - (dy / len) * 127);
        normal[i + 2] = Math.round(128 + 127 / len);
        normal[i + 3] = 255;
      }
    const bump = RawTexture.CreateRGBATexture(
      normal,
      size,
      size,
      scene,
      true,
      false,
    );
    bump.name = 'cast-armor-micro-normal';
    bump.gammaSpace = false;
    bump.uScale = bump.vScale = 7;
    bump.level = 0.32;
    armor.bumpTexture = enemy.bumpTexture = heavy.bumpTexture = bump;
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
    mud,
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
