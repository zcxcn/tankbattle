import { applySurface } from './surface-textures';
import {
  Color3,
  PBRMaterial,
  RawTexture,
  Scene,
  StandardMaterial,
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
  m.enableSpecularAntiAliasing = true;
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
  const armor = pbr(scene, 'olive-composite-armor', '#727963', 0.06, 0.72),
    enemy = pbr(scene, 'scorched-enemy-armor', '#766454', 0.06, 0.78),
    heavy = pbr(scene, 'siege-armor', '#454743', 0.09, 0.69),
    steel = pbr(scene, 'blackened-steel', '#535957', 0.88, 0.4),
    rubber = pbr(scene, 'track-rubber', '#171a18', 0.06, 0.95),
    edges = pbr(scene, 'edge-wear-metal', '#91948b', 0.8, 0.5),
    mud = pbr(scene, 'dried-track-mud', '#514538', 0, 0.97),
    ground = pbr(scene, 'weathered-concrete-paving', '#b5b4a9', 0, 0.95),
    concrete = pbr(scene, 'old-concrete', '#cecbc1', 0.02, 0.97),
    brick = pbr(scene, 'exposed-brick', '#e4d5c4', 0.02, 0.98),
    glass = pbr(scene, 'optical-glass', '#1a3937', 0.04, 0.16);
  if (assets) {
    for (const painted of [armor, enemy, heavy])
      applySurface(painted, scene, 'armor', { mobile, strength: 0.28 });
    applySurface(ground, scene, 'concrete', {
      repeat: 20,
      mobile,
      strength: 0.48,
    });
    applySurface(concrete, scene, 'concrete', { mobile, strength: 0.6 });
    applySurface(brick, scene, 'brick', { mobile, strength: 0.72 });
  }
  const lamp = emissive(scene, 'warm-headlights', '#ffdfad', 2.4),
    red = emissive(scene, 'enemy-optics', '#ff744a', 1.8),
    blue = emissive(scene, 'energy-blue', '#7fcbd3', 1.6),
    ember = emissive(scene, 'molten-fire', '#ff9c39', 2.4),
    white = emissive(scene, 'tracer-core', '#fff1b0', 2.8),
    marking = pbr(scene, 'faded-marking', '#ddd9b4', 0.05, 0.8);
  // One shared analytic occlusion mask for vehicle undersides. This small,
  // feathered footprint remains useful when dynamic shadows are budgeted off.
  const size = 64,
    pixels = new Uint8Array(size * size * 4);
  for (let y = 0; y < size; y++)
    for (let x = 0; x < size; x++) {
      const nx = Math.abs(((x + 0.5) / size) * 2 - 1),
        ny = Math.abs(((y + 0.5) / size) * 2 - 1),
        edge = Math.min(
          1,
          Math.max(0, (1 - Math.pow(nx ** 4 + ny ** 4, 0.25)) / 0.38),
        );
      pixels[(y * size + x) * 4 + 3] = Math.round(
        100 * edge * edge * (3 - 2 * edge),
      );
    }
  const contactTexture = RawTexture.CreateRGBATexture(
    pixels,
    size,
    size,
    scene,
    false,
    false,
  );
  contactTexture.name = 'shared-vehicle-contact-occlusion';
  contactTexture.hasAlpha = true;
  const contact = emissive(scene, 'vehicle-contact-shadow', '#080b10');
  contact.diffuseTexture = contactTexture;
  contact.useAlphaFromDiffuseTexture = true;
  contact.disableDepthWrite = true;
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
    contact,
  };
}
export type Materials = ReturnType<typeof createMaterials>;
