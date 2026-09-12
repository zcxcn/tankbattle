import { CreateBoxVertexData } from '@babylonjs/core/Meshes/Builders/boxBuilder.js';
import { CreateCylinderVertexData } from '@babylonjs/core/Meshes/Builders/cylinderBuilder.js';
import { Geometry } from '@babylonjs/core/Meshes/geometry.js';
import {
  Matrix,
  Mesh,
  MeshBuilder,
  Scene,
  TransformNode,
  VertexData,
  type Material,
} from './babylon';
import { pbr, type Materials, type Quality } from './materials';

type Batch = {
  positions: number[];
  normals: number[];
  uvs: number[];
  indices: number[];
  material: Material;
  parts: string[];
};
type Part = { geometry: Geometry; material: Material; parts: string[] };
type PrototypeSet = { variants: Part[][]; accent: Geometry; slots: number };
type SupplyState = {
  set: PrototypeSet;
  slots: Mesh[];
  accent: Mesh;
  label: Mesh;
  family: number;
  type: number;
};
const prototypes = new WeakMap<Scene, PrototypeSet>();
const states = new WeakMap<TransformNode, SupplyState>();
const unitBox = CreateBoxVertexData({ size: 1 });

function createPrototypes(
  scene: Scene,
  materials: Materials,
  quality: Quality,
): PrototypeSet {
  const low = quality === 'performance',
    brass = pbr(scene, 'supply-shell-brass', '#b59c62', 0.68, 0.49),
    repair = pbr(scene, 'supply-toolbox-red', '#995346', 0.08, 0.79),
    cell = pbr(scene, 'supply-cell-ceramic', '#62868a', 0.22, 0.54);
  const variants: Part[][] = [];
  let accent: Geometry | null = null;
  for (let family = 0; family < 4; family++) {
    const groups = new Map<Material, Batch>();
    const primitive = (
      name: string,
      vertex: VertexData,
      size: number[],
      at: number[],
      material: Material,
      rotation = [0, 0, 0],
    ) => {
      let data = groups.get(material);
      if (!data) {
        data = {
          positions: [],
          normals: [],
          uvs: [],
          indices: [],
          material,
          parts: [],
        };
        groups.set(material, data);
      }
      data.parts.push(name);
      const start = data.positions.length / 3,
        transform = Matrix.RotationYawPitchRoll(
          rotation[1],
          rotation[0],
          rotation[2],
        ).m;
      for (let i = 0; i < vertex.positions!.length; i += 3) {
        const x = vertex.positions![i] * size[0],
          y = vertex.positions![i + 1] * size[1],
          z = vertex.positions![i + 2] * size[2],
          nx = vertex.normals![i],
          ny = vertex.normals![i + 1],
          nz = vertex.normals![i + 2];
        data.positions.push(
          x * transform[0] + y * transform[4] + z * transform[8] + at[0],
          x * transform[1] + y * transform[5] + z * transform[9] + at[1],
          x * transform[2] + y * transform[6] + z * transform[10] + at[2],
        );
        data.normals.push(
          nx * transform[0] + ny * transform[4] + nz * transform[8],
          nx * transform[1] + ny * transform[5] + nz * transform[9],
          nx * transform[2] + ny * transform[6] + nz * transform[10],
        );
        data.uvs.push(vertex.uvs![(i / 3) * 2], vertex.uvs![(i / 3) * 2 + 1]);
      }
      for (const index of vertex.indices!) data.indices.push(start + index);
    };
    const box = (
      name: string,
      size: number[],
      at: number[],
      material: Material,
      rotation?: number[],
    ) => primitive(name, unitBox, size, at, material, rotation);
    const cylinder = (
      name: string,
      height: number,
      bottom: number,
      top: number,
      at: number[],
      material: Material,
      rotation?: number[],
      tessellation = low ? 8 : 12,
    ) =>
      primitive(
        name,
        CreateCylinderVertexData({
          height,
          diameterBottom: bottom,
          diameterTop: top,
          tessellation,
        }),
        [1, 1, 1],
        at,
        material,
        rotation,
      );
    box(
      'shockproof-case-base',
      [3.4, 0.24, 2.42],
      [0, 0.2, 0],
      materials.rubber,
    );
    for (const side of [-1, 1]) {
      box(
        'case-steel-corner',
        [0.18, 0.72, 0.22],
        [side * 1.52, 0.67, 1.08],
        materials.steel,
      );
      box(
        'case-latch',
        [0.25, 0.3, 0.12],
        [side * 0.98, 0.75, 1.19],
        materials.edges,
      );
      box(
        'latch-lock-pin',
        [0.07, 0.11, 0.045],
        [side * 0.98, 0.75, 1.265],
        materials.rubber,
      );
    }
    if (family === 3) {
      box('ammo-crate-tray', [3.2, 0.45, 2.2], [0, 0.54, 0], materials.armor);
      for (const side of [-1, 1])
        box(
          'ammo-crate-side-wall',
          [0.16, 0.7, 2.2],
          [side * 1.52, 0.88, 0],
          materials.armor,
        );
      box(
        'ammo-crate-open-lid',
        [3.2, 0.8, 0.12],
        [0, 1.1, -1.04],
        materials.armor,
      );
      box(
        'ammo-crate-lid-reinforcement',
        [2.95, 0.07, 0.07],
        [0, 1.3, -0.955],
        materials.edges,
      );
      for (const side of [-1, 1])
        box(
          'shell-rack-support',
          [2.8, 0.14, 0.12],
          [0, 0.9, side * 0.58],
          materials.rubber,
        );
      for (let shell = -1; shell <= 1; shell++) {
        const x = shell * 0.76;
        cylinder(
          'exposed-ammunition-shell',
          1.18,
          0.43,
          0.43,
          [x, 1.06, 0.14],
          brass,
          [Math.PI / 2, 0, 0],
        );
        cylinder(
          'shell-ogive-tip',
          0.5,
          0.43,
          0.065,
          [x, 1.06, -0.7],
          materials.steel,
          [-Math.PI / 2, 0, 0],
        );
        cylinder('shell-rim', 0.085, 0.49, 0.49, [x, 1.06, 0.765], brass, [
          Math.PI / 2,
          0,
          0,
        ]);
        cylinder(
          'shell-primer',
          0.09,
          0.17,
          0.17,
          [x, 1.06, 0.78],
          materials.rubber,
          [Math.PI / 2, 0, 0],
        );
      }
    } else if (family === 0) {
      box('repair-toolbox-body', [3.18, 0.93, 2.18], [0, 0.78, 0], repair);
      box('repair-toolbox-lid', [3.28, 0.18, 2.25], [0, 1.33, 0], repair);
      box(
        'toolbox-lid-seam',
        [3.23, 0.035, 2.22],
        [0, 1.21, 0],
        materials.rubber,
      );
      for (const side of [-1, 1])
        box(
          'toolbox-handle-foot',
          [0.12, 0.33, 0.16],
          [side * 0.55, 1.56, -0.3],
          materials.steel,
        );
      box(
        'toolbox-grip',
        [1.23, 0.17, 0.19],
        [0, 1.75, -0.3],
        materials.rubber,
      );
      box(
        'socket-wrench-shaft',
        [0.16, 0.085, 1.38],
        [-0.9, 1.5, 0.1],
        materials.edges,
        [0, -0.45, 0],
      );
      cylinder(
        'socket-wrench-head',
        0.12,
        0.41,
        0.41,
        [-1.19, 1.51, -0.47],
        materials.edges,
      );
      cylinder(
        'socket-wrench-recess',
        0.125,
        0.21,
        0.21,
        [-1.19, 1.52, -0.47],
        materials.rubber,
        undefined,
        6,
      );
      box(
        'screwdriver-grip',
        [0.23, 0.16, 0.53],
        [0.91, 1.52, 0.51],
        repair,
        [0, 0.25, 0],
      );
      box(
        'screwdriver-shaft',
        [0.055, 0.055, 0.69],
        [0.78, 1.5, -0.06],
        materials.edges,
        [0, 0.25, 0],
      );
      for (let rib = 0; rib < 3; rib++)
        box(
          'toolbox-reinforcing-rib',
          [0.095, 0.74, 0.045],
          [(rib - 1) * 0.62, 0.77, 1.12],
          repair,
        );
    } else if (family === 1) {
      box(
        'overclock-power-pack-tray',
        [3.17, 0.43, 2.19],
        [0, 0.53, 0],
        materials.heavy,
      );
      for (const side of [-1, 1]) {
        cylinder(
          'overclock-capacitor',
          1.15,
          0.82,
          0.82,
          [side * 0.74, 1.09, 0],
          brass,
        );
        cylinder(
          'capacitor-terminal-cap',
          0.17,
          0.89,
          0.89,
          [side * 0.74, 1.71, 0],
          materials.steel,
        );
        cylinder(
          'capacitor-insulating-ring',
          0.14,
          0.89,
          0.89,
          [side * 0.74, 1.39, 0],
          materials.rubber,
        );
        box(
          'power-pack-terminal',
          [0.21, 0.2, 0.25],
          [side * 0.74, 1.88, 0],
          materials.edges,
        );
      }
      for (let fin = 0; fin < (low ? 5 : 8); fin++)
        box(
          'charging-unit-cooling-fin',
          [2.45, 0.065, 0.38],
          [0, 0.67 + fin * 0.115, -0.9],
          materials.steel,
        );
      box(
        'power-pack-carry-bar',
        [2.43, 0.11, 0.14],
        [0, 1.16, 1.01],
        materials.edges,
      );
    } else {
      box('armored-cell-tray', [3.2, 0.4, 2.2], [0, 0.54, 0], materials.armor);
      cylinder(
        'shield-cell-core',
        1.26,
        1.28,
        1.13,
        [0, 1.15, 0],
        cell,
        undefined,
        8,
      );
      cylinder(
        'shield-cell-top-collar',
        0.16,
        1.44,
        1.44,
        [0, 1.8, 0],
        materials.edges,
        undefined,
        8,
      );
      cylinder(
        'shield-cell-bottom-collar',
        0.16,
        1.47,
        1.47,
        [0, 0.57, 0],
        materials.steel,
        undefined,
        8,
      );
      for (const side of [-1, 1]) {
        box(
          'shield-cell-armor-panel',
          [0.67, 1.23, 1.42],
          [side * 1.04, 1.03, 0],
          materials.armor,
          [0, 0, side * 0.16],
        );
        box(
          'shield-cell-panel-ridge',
          [0.11, 1.05, 1.49],
          [side * 1.03, 1.08, 0],
          materials.edges,
          [0, 0, side * 0.16],
        );
        cylinder(
          'shield-cell-terminal',
          0.17,
          0.22,
          0.22,
          [side * 0.37, 1.95, 0],
          materials.edges,
        );
      }
      for (let band = 0; band < 3; band++)
        cylinder(
          'shield-cell-insulator',
          0.085,
          1.32,
          1.26,
          [0, 0.87 + band * 0.29, 0],
          materials.rubber,
          undefined,
          8,
        );
    }
    const parts: Part[] = [];
    for (const [material, batch] of groups) {
      const data = new VertexData();
      data.positions = batch.positions;
      data.normals = batch.normals;
      data.uvs = batch.uvs;
      data.indices = batch.indices;
      parts.push({
        geometry: new Geometry(
          'supply-family-' + family + '-' + parts.length,
          scene,
          data,
          false,
        ),
        material,
        parts: batch.parts,
      });
    }
    variants.push(parts);
    if (!accent) {
      const data = CreateBoxVertexData({
        width: 1.23,
        height: 0.16,
        depth: 0.035,
      });
      for (let i = 0; i < data.positions!.length; i += 3) {
        data.positions![i + 1] += 0.96;
        data.positions![i + 2] += 1.23;
      }
      accent = new Geometry(
        'supply-small-identification-strip',
        scene,
        data,
        false,
      );
    }
  }
  // Register every shared buffer once so unused variants also follow scene disposal.
  for (const parts of variants)
    for (const part of parts) scene.pushGeometry(part.geometry);
  scene.pushGeometry(accent!);
  brass.freeze();
  repair.freeze();
  cell.freeze();
  return {
    variants,
    accent: accent!,
    slots: Math.max(...variants.map((v) => v.length)),
  };
}

/** Geometry is built once per scene. Pool slots only rebind shared buffers when
 * pickup families change; no crosses, beams, per-frame meshes, or cloned mats. */
export function createSupplyModel(
  scene: Scene,
  materials: Materials,
  quality: Quality,
): TransformNode {
  let set = prototypes.get(scene);
  if (!set) {
    set = createPrototypes(scene, materials, quality);
    prototypes.set(scene, set);
  }
  const root = new TransformNode('field-supply', scene),
    slots: Mesh[] = [];
  for (let index = 0; index < set.slots; index++) {
    const mesh = new Mesh(
      index === 0 ? 'supply-case' : 'supply-detail-' + index,
      scene,
    );
    mesh.parent = root;
    mesh.isPickable = false;
    mesh.receiveShadows = true;
    slots.push(mesh);
  }
  const accent = new Mesh('supply-identification-strip', scene);
  set.accent.applyToMesh(accent);
  accent.parent = root;
  accent.isPickable = false;
  const label = MeshBuilder.CreatePlane(
    'supply-label',
    { width: 4.8, height: 1.5 },
    scene,
  );
  label.parent = root;
  label.position.y = 3.55;
  label.billboardMode = Mesh.BILLBOARDMODE_ALL;
  label.isPickable = false;
  states.set(root, { set, slots, accent, label, family: -1, type: -1 });
  return root;
}
export function configureSupplyModel(
  root: TransformNode,
  kind: number,
  type: number,
  color: Material,
  label: Material,
) {
  const state = states.get(root)!;
  const family = kind === 3 ? 3 : kind === 0 ? 0 : kind === 1 ? 1 : 2;
  if (state.family !== family) {
    const parts = state.set.variants[family];
    for (let index = 0; index < state.slots.length; index++) {
      const mesh = state.slots[index],
        part = parts[index];
      mesh.setEnabled(!!part);
      if (part) {
        part.geometry.applyToMesh(mesh);
        mesh.material = part.material;
        mesh.metadata = { supplyFamily: family, parts: part.parts };
      }
    }
    state.family = family;
    root.metadata = { supplyFamily: family };
  }
  if (state.type !== type) {
    state.accent.material = color;
    state.label.material = label;
    state.type = type;
  }
}
