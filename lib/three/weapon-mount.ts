import { Mesh, Scene, TransformNode, type Material } from './babylon';
import { type Materials } from './materials';
import {
  armoredHull,
  box,
  mergeByMaterial,
  turnedPart,
  type TankModel,
} from './tank-model';

/** Replace only the gun attachment, keeping the chassis, evolution and aim intact. */
export function createWeaponMount(
  scene: Scene,
  model: TankModel,
  index: number,
  materials: Materials,
) {
  for (const mesh of model.barrel.getChildMeshes(true))
    if (mesh !== model.flash) mesh.setEnabled(index === 0);
  const root = new TransformNode('equipped-weapon-' + index, scene);
  root.parent = model.barrel;
  const add = (
    name: string,
    size: number[],
    at: number[],
    material: Material = materials.steel,
  ) => box(scene, name, size, at, material, root);
  const tube = (
    name: string,
    section: [number, number][],
    material: Material = materials.steel,
    x = 0,
    y = 0.5,
    segments = 16,
  ) => {
    const mesh = turnedPart(scene, name, section, material, root, segments);
    mesh.position.set(x, y, 0);
    return mesh;
  };
  const collar = (
    name: string,
    z: number,
    radius: number,
    material: Material = materials.steel,
  ) =>
    tube(
      name,
      [
        [z, radius],
        [z + 0.065, radius],
        [z + 0.065, radius - 0.035],
        [z, radius - 0.035],
      ],
      material,
    );
  const housing = (
    name: string,
    width: number,
    length: number,
    z: number,
    low: number,
    high: number,
    material: Material = materials.armor,
  ) => {
    const mesh = armoredHull(
      scene,
      name + '-turret-housing',
      width,
      length,
      low,
      high,
      root,
      material,
    );
    mesh.position.z = z;
    return mesh;
  };

  // Every launch axis ends at the existing shared muzzle, y=.5, z=4.06.
  // Open inner walls replace black discs pasted onto solid end caps.
  if (index === 1) {
    housing(
      'machinegun-receiver',
      0.56,
      1.28,
      1.85,
      0.26,
      0.74,
      materials.steel,
    );
    tube('heavy-machinegun-open-barrel', [
      [1.86, 0.11],
      [3.66, 0.078],
      [3.76, 0.105],
      [4.06, 0.095],
      [4.06, 0.055],
      [1.86, 0.055],
    ]);
    // The central bore matches the simulated bullet; the guard has real gaps.
    for (const z of [2.34, 2.87, 3.4])
      collar('machinegun-guard-ring', z, 0.175);
    for (const angle of [0, Math.PI / 2, Math.PI, Math.PI * 1.5]) {
      const rail = add(
        'machinegun-guard-rib',
        [0.045, 0.045, 1.12],
        [Math.cos(angle) * 0.15, 0.5 + Math.sin(angle) * 0.15, 2.92],
      );
      rail.rotation.z = angle;
    }
    const feed = add(
      'machinegun-feed-chute',
      [0.37, 0.19, 0.34],
      [0.35, 0.52, 1.64],
    );
    feed.rotation.z = -0.18;
    add(
      'machinegun-feed-container',
      [0.48, 0.55, 0.77],
      [0.68, 0.43, 1.57],
      materials.armor,
    );
    add('machinegun-top-cover', [0.28, 0.04, 0.66], [0, 0.75, 1.77]);
  } else if (index === 6) {
    housing('rocket-pod', 1.3, 2.28, 2.65, 0.01, 0.99);
    for (const [x, y] of [
      [0, 0.5],
      [-0.38, 0.75],
      [0.38, 0.75],
      [-0.38, 0.22],
      [0.38, 0.22],
    ]) {
      tube(
        'rocket-launch-tube-open-mouth',
        [
          [3.5, 0.183],
          [3.96, 0.183],
          [4.06, 0.167],
          [4.06, 0.137],
          [3.5, 0.137],
        ],
        materials.steel,
        x,
        y,
      );
      tube(
        'rocket-rear-vent',
        [
          [1.37, 0.15],
          [1.54, 0.15],
          [1.54, 0.11],
          [1.37, 0.11],
        ],
        materials.steel,
        x,
        y,
        10,
      );
    }
    for (const side of [-1, 1])
      add('rocket-pod-cradle', [0.1, 0.66, 1.42], [side * 0.67, 0.5, 2.45]);
    add('rocket-targeting-sight-housing', [0.25, 0.2, 0.58], [0, 1.06, 2.4]);
    add(
      'rocket-targeting-sight-lens',
      [0.17, 0.1, 0.025],
      [0, 1.06, 2.7],
      materials.glass,
    );
  } else if (index === 3) {
    housing('railgun-capacitor', 0.9, 1.16, 1.65, 0.13, 0.88, materials.heavy);
    for (const side of [-1, 1]) {
      add(
        'railgun-magnetic-rail',
        [0.2, 0.27, 2.55],
        [side * 0.22, 0.5, 2.785],
      );
      add(
        'railgun-ceramic-insulator',
        [0.08, 0.19, 2.36],
        [side * 0.32, 0.5, 2.82],
        materials.armor,
      );
      add(
        'railgun-energy-channel',
        [0.025, 0.065, 2.3],
        [side * 0.115, 0.5, 2.8],
        materials.blue,
      );
      for (const z of [1.9, 2.4, 2.9])
        add('railgun-rail-clamp', [0.17, 0.39, 0.11], [side * 0.32, 0.5, z]);
    }
    add('railgun-recoil-cradle', [0.58, 0.12, 1.4], [0, 0.29, 2.05]);
  } else if (index > 0) {
    const radius = index === 2 ? 0.32 : index === 4 ? 0.265 : 0.18,
      bore = index === 2 ? 0.25 : index === 4 ? 0.2 : 0.115;
    housing('specialist-breech', radius * 2.5, 1.25, 1.78, 0.16, 0.84);
    tube('specialist-open-barrel', [
      [1.7, radius],
      [2.25, radius],
      [2.4, radius * 0.9],
      [3.68, radius * 0.9],
      [3.83, radius],
      [4.06, radius],
      [4.06, bore],
      [1.7, bore],
    ]);
    if (index === 2) {
      for (const z of [2.42, 3.3])
        collar('shotgun-retaining-collar', z, radius + 0.025);
      add('shotgun-reinforced-cradle', [0.45, 0.12, 1.66], [0, 0.22, 2.44]);
    } else if (index === 4) {
      for (const side of [-1, 1]) {
        tube(
          'grenade-recoil-cylinder',
          [
            [1.45, 0.1],
            [2.52, 0.1],
            [2.58, 0.072],
            [1.45, 0.072],
          ],
          materials.armor,
          side * 0.34,
          0.57,
          12,
        );
        tube(
          'grenade-recuperator-rod',
          [
            [2.46, 0.043],
            [3.13, 0.043],
            [3.13, 0.02],
            [2.46, 0.02],
          ],
          materials.edges,
          side * 0.34,
          0.57,
          10,
        );
      }
      collar('grenade-forward-support', 3.04, radius + 0.03);
      add(
        'grenade-ammunition-band',
        [0.035, 0.055, 0.45],
        [0.37, 0.63, 1.77],
        materials.marking,
      );
    } else {
      for (const z of [2.05, 2.25, 2.45, 2.65, 2.85])
        collar('cryo-heat-exchanger-fin', z, radius + 0.12, materials.edges);
      for (const z of [1.85, 3.05])
        collar('cryo-field-indicator', z, radius + 0.055, materials.blue);
      for (const side of [-1, 1])
        tube(
          'cryo-pressure-vessel',
          [
            [1.25, 0.09],
            [1.36, 0.14],
            [2.25, 0.14],
            [2.38, 0.09],
            [2.38, 0.07],
            [1.25, 0.07],
          ],
          materials.armor,
          side * 0.38,
          0.51,
          12,
        );
    }
  }
  // Switching guns disposes these material batches through the existing root.
  const meshes: Mesh[] = mergeByMaterial(root);
  for (const mesh of meshes) {
    mesh.isPickable = false;
    mesh.metadata = { tankId: 0, weapon: index };
  }
  return { model, index, root, meshes };
}
