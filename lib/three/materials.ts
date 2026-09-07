import { applySurface } from './surface-textures';
import { Color3, PBRMaterial, Scene, StandardMaterial } from './babylon';
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
    ground = pbr(scene, 'weathered-concrete-paving', '#c5c6bf', 0.02, 0.95),
    concrete = pbr(scene, 'old-concrete', '#cecbc1', 0.02, 0.97),
    brick = pbr(scene, 'exposed-brick', '#e4d5c4', 0.02, 0.98),
    glass = pbr(scene, 'optical-glass', '#1a3937', 0.75, 0.16);
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
