import {
  Mesh,
  MeshBuilder,
  Scene,
  TransformNode,
  type Material,
} from './babylon';
import { type Materials } from './materials';
import { box, type TankModel } from './tank-model';

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
  const meshes: Mesh[] = [];
  const add = (
    name: string,
    size: number[],
    at: number[],
    material: Material = materials.steel,
  ) => {
    const mesh = box(scene, name, size, at, material, root);
    meshes.push(mesh);
    return mesh;
  };
  const tube = (
    name: string,
    radius: number,
    length: number,
    x: number,
    y: number,
    z: number,
    material: Material = materials.steel,
  ) => {
    const mesh = MeshBuilder.CreateCylinder(
      name,
      { diameter: radius * 2, height: length, tessellation: 10 },
      scene,
    );
    mesh.position.set(x, y, z);
    mesh.rotation.x = Math.PI / 2;
    mesh.material = material;
    mesh.parent = root;
    meshes.push(mesh);
    return mesh;
  };
  if (index === 1) {
    tube('machinegun-receiver', 0.28, 1.2, 0, 0.5, 1.65);
    for (let i = 0; i < 6; i++) {
      const a = (i / 6) * Math.PI * 2;
      tube(
        'machinegun-barrel',
        0.07,
        2.3,
        Math.cos(a) * 0.17,
        0.5 + Math.sin(a) * 0.17,
        2.86,
      );
    }
    add(
      'machinegun-ammo-box',
      [0.6, 0.55, 0.9],
      [0.5, 0.45, 1.4],
      materials.armor,
    );
  } else if (index === 6) {
    add(
      'rocket-launcher-body',
      [1.28, 0.96, 2.28],
      [0, 0.5, 2.65],
      materials.armor,
    );
    for (const [x, y] of [
      [0, 0.5],
      [-0.38, 0.75],
      [0.38, 0.75],
      [-0.38, 0.22],
      [0.38, 0.22],
    ]) {
      tube('rocket-launch-tube', 0.18, 0.38, x, y, 3.86, materials.edges);
      tube('rocket-launcher-bore', 0.135, 0.016, x, y, 4.057, materials.rubber);
    }
    add(
      'rocket-targeting-sight',
      [0.23, 0.2, 0.6],
      [0, 1.09, 2.4],
      materials.red,
    );
  } else if (index === 3) {
    for (const x of [-0.22, 0.22]) {
      add(
        'railgun-magnetic-rail',
        [0.19, 0.28, 2.85],
        [x, 0.5, 2.55],
        materials.steel,
      );
      add(
        'railgun-energy-channel',
        [0.045, 0.11, 2.6],
        [x * 0.58, 0.5, 2.65],
        materials.blue,
      );
    }
    add('railgun-capacitor', [0.84, 0.7, 0.85], [0, 0.5, 1.2], materials.heavy);
  } else if (index > 0) {
    tube(
      'specialist-gun-barrel',
      index === 2 ? 0.36 : index === 4 ? 0.31 : 0.19,
      2.65,
      0,
      0.5,
      2.65,
    );
    tube(
      'specialist-gun-bore',
      index === 2 ? 0.29 : index === 4 ? 0.24 : 0.14,
      0.018,
      0,
      0.5,
      3.99,
      materials.rubber,
    );
    for (let i = 0; i < 4; i++)
      tube(
        'gun-cooling-collar',
        index === 2 ? 0.4 : 0.36,
        0.13,
        0,
        0.5,
        1.65 + i * 0.5,
        index === 5
          ? materials.blue
          : index === 4
            ? materials.ember
            : materials.edges,
      );
  }
  for (const mesh of meshes) {
    mesh.isPickable = false;
    mesh.metadata = { tankId: 0, weapon: index };
  }
  return { model, index, root, meshes };
}
