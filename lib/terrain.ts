import { type Battlefield, type TerrainFeature } from './battlefields';
export type Road = { x: number; y: number; w: number; h: number };
export const ARENA_MARGIN = 25;
export const enemyEntrances = (width: number) =>
  [0.22, 0.5, 0.78].map((fraction) => ({ x: width * fraction, y: 110 }));
export type Structure = Road & {
  kind:
    | 'warehouse'
    | 'office'
    | 'container'
    | 'barrier'
    | 'tree'
    | 'hedge'
    | 'boundary'
    | 'water'
    | 'hill';
  height: number;
  steel: boolean;
  hp: number;
  maxHp: number;
};

export function boundaryWalls(width: number, height: number): Structure[] {
  const inset = ARENA_MARGIN;
  return [
    { x: 0, y: 0, w: inset, h: height },
    { x: width - inset, y: 0, w: inset, h: height },
    { x: inset, y: 0, w: width - inset * 2, h: inset },
    { x: inset, y: height - inset, w: width - inset * 2, h: inset },
  ].map((rect) => ({
    ...rect,
    kind: 'boundary',
    height: 3.2,
    steel: true,
    hp: Infinity,
    maxHp: Infinity,
  }));
}

/** All solid scenery has this exact footprint in both simulation and renderer. */
export function cityLayout(mission: number, width: number, height: number) {
  const roads: Road[] = [];
  const xs = [0.22, 0.36, 0.5, 0.64, 0.78].map((x) => width * x);
  const ys = [
    300,
    height * 0.27,
    height * 0.4,
    height * 0.52,
    height * 0.64,
    height * 0.78,
    height - 240,
  ];
  for (const x of xs) roads.push({ x: x - 65, y: 0, w: 130, h: height });
  for (const y of ys) roads.push({ x: 0, y: y - 60, w: width, h: 120 });
  const structures: Structure[] = [];
  const add = (
    x: number,
    y: number,
    w: number,
    h: number,
    kind: Structure['kind'],
    high: number,
  ) => {
    const hp =
      kind === 'office'
        ? 560
        : kind === 'warehouse'
          ? 380
          : kind === 'container'
            ? 220
            : kind === 'tree'
              ? 180
              : kind === 'hedge'
                ? 75
                : 130;
    structures.push({
      x,
      y,
      w,
      h,
      kind,
      height: high,
      steel: false,
      hp,
      maxHp: hp,
    });
  };
  const edgesX = [40, ...xs, width - 40],
    edgesY = [30, ...ys, height - 25];
  for (let row = 0; row < edgesY.length - 1; row++) {
    for (let col = 0; col < edgesX.length - 1; col++) {
      const x = edgesX[col] + 105,
        y = edgesY[row] + 88;
      const w = edgesX[col + 1] - x - 100,
        h = edgesY[row + 1] - y - 90;
      if (h < 65 || w < 140) continue;
      const variant = (row * 7 + col * 3 + mission) % 4;
      // Open loading apron and a real service alley separate the two buildings.
      const gap = 95,
        half = (w - gap) / 2;
      add(
        x,
        y,
        half,
        h,
        variant === 0 ? 'office' : 'warehouse',
        variant === 0
          ? (row + col + mission) % 4 === 0
            ? 16 + (col % 3) * 2.5
            : 7.6
          : 4.2,
      );
      add(
        x + half + gap,
        y,
        half,
        h * 0.72,
        variant === 2 ? 'office' : 'warehouse',
        variant === 2
          ? (row + col + mission) % 4 === 0
            ? 15 + (row % 3) * 2.5
            : 6.8
          : 3.8,
      );
      if (h > 130) add(x + half + gap, y + h - 30, 90, 26, 'container', 2.6);
      // Roadside checkpoints are destructible and never close an entire street.
      if ((row + col + mission) % 2 === 0)
        add(x + half + 16, y + 24, 56, 24, 'barrier', 1.5);
      // Trunks sit beyond the street shoulder. They share collision/clearance
      // filtering with buildings, so objectives and convoy routes remain open.
      add(x - 37, y + 12, 14, 14, 'tree', 6 + variant * 0.65);
      add(
        x + w + 23,
        y + Math.max(28, h * 0.55),
        14,
        14,
        'tree',
        6.8 + variant * 0.5,
      );
      if (h > 150)
        add(
          x + half + gap + 8,
          y + h * 0.72 + 10,
          Math.max(35, half - 16),
          12,
          'hedge',
          1.15,
        );
    }
  }
  return { roads, structures };
}

/** Each biome has its own roads and obstacle arrangement; these rectangles are
 * also the renderer's terrain contract, including actual gaps under bridges. */
export function battlefieldLayout(
  field: Battlefield,
  mission: number,
  width: number,
  height: number,
) {
  const decorations: TerrainFeature[] = [];
  if (field.id === 'city')
    return { ...cityLayout(mission, width, height), decorations };
  const roads: Road[] = [];
  const structures: Structure[] = [];
  const road = (x: number, y: number, w: number, h: number) =>
    roads.push({ x: x * width, y: y * height, w: w * width, h: h * height });
  const add = (
    kind: Structure['kind'],
    x: number,
    y: number,
    w: number,
    h: number,
    high: number,
  ) => {
    const permanent = kind === 'hill' || kind === 'water';
    const hp = permanent
      ? Infinity
      : kind === 'office'
        ? 560
        : kind === 'warehouse'
          ? 380
          : kind === 'container'
            ? 220
            : kind === 'tree'
              ? 180
              : 130;
    structures.push({
      kind,
      x: x * width,
      y: y * height,
      w: w * width,
      h: h * height,
      height: high,
      steel: permanent,
      hp,
      maxHp: hp,
    });
  };
  const decor = (
    kind: TerrainFeature['kind'],
    x: number,
    y: number,
    w: number,
    h: number,
    high: number,
  ) =>
    decorations.push({
      kind,
      x: x * width,
      y: y * height,
      w: w * width,
      h: h * height,
      height: high,
    });
  const trees = (x: number, y: number, count: number, spread = 0.018) => {
    for (let i = 0; i < count; i++)
      add(
        'tree',
        x + (i % 4) * spread + Math.sin(i * 2.4 + x * 29) * spread * 0.33,
        y +
          Math.floor(i / 4) * spread * 1.5 +
          Math.cos(i * 1.7 + y * 47) * spread * 0.38,
        0.004,
        0.006,
        6 + (i % 3),
      );
  };
  if (field.id === 'highlands') {
    road(0.477, 0, 0.046, 1);
    road(0.18, 0.6, 0.64, 0.07);
    road(0.75, 0.1, 0.055, 0.79);
    for (const [x, y, w, h] of [
      [0.07, 0.17, 0.1, 0.14],
      [0.29, 0.28, 0.13, 0.16],
      [0.57, 0.13, 0.12, 0.17],
      [0.86, 0.28, 0.08, 0.19],
      [0.06, 0.7, 0.12, 0.14],
      [0.3, 0.73, 0.11, 0.12],
      [0.59, 0.7, 0.12, 0.13],
      [0.85, 0.65, 0.1, 0.2],
    ])
      add('hill', x, y, w, h, 11 + ((x * 30) % 4));
    add('warehouse', 0.29, 0.49, 0.064, 0.072, 4.2);
    add('office', 0.6, 0.46, 0.058, 0.07, 6);
    trees(0.24, 0.16, 12);
    trees(0.53, 0.77, 12);
    trees(0.81, 0.49, 16);
    trees(0.09, 0.47, 8);
  } else if (field.id === 'desert') {
    road(0.055, 0.84, 0.89, 0.072);
    road(0.47, 0.12, 0.065, 0.76);
    road(0.15, 0.36, 0.69, 0.065);
    for (const [x, y, w, h] of [
      [0.06, 0.2, 0.1, 0.11],
      [0.32, 0.48, 0.09, 0.14],
      [0.6, 0.19, 0.1, 0.12],
      [0.86, 0.57, 0.08, 0.18],
      [0.1, 0.66, 0.1, 0.12],
    ])
      add('hill', x, y, w, h, 8.5);
    for (const [x, y] of [
      [0.28, 0.2],
      [0.68, 0.69],
      [0.56, 0.48],
    ]) {
      add('warehouse', x, y, 0.055, 0.064, 3.8);
      add('container', x + 0.065, y + 0.008, 0.028, 0.024, 2.4);
      add('barrier', x + 0.013, y + 0.079, 0.037, 0.014, 1.5);
    }
    trees(0.24, 0.73, 4, 0.027);
  } else if (field.id === 'tropical') {
    road(0.19, 0.07, 0.055, 0.87);
    road(0.19, 0.59, 0.64, 0.09);
    road(0.75, 0.13, 0.055, 0.78);
    road(0.24, 0.255, 0.49, 0.07);
    for (const [y, h] of [
      [0.045, 0.19],
      [0.35, 0.205],
      [0.72, 0.22],
    ])
      add('water', 0.34, y, 0.065, h, 0.04);
    add('water', 0.6, 0.73, 0.075, 0.17, 0.04);
    decor('bridge', 0.332, 0.235, 0.081, 0.115, 0.1);
    decor('bridge', 0.332, 0.555, 0.081, 0.165, 0.1);
    add('hill', 0.08, 0.4, 0.095, 0.14, 9);
    add('hill', 0.86, 0.17, 0.08, 0.16, 12);
    add('warehouse', 0.61, 0.28, 0.072, 0.07, 3.8);
    add('warehouse', 0.1, 0.73, 0.065, 0.06, 3.5);
    for (const [x, y] of [
      [0.08, 0.21],
      [0.27, 0.43],
      [0.43, 0.46],
      [0.58, 0.57],
      [0.84, 0.53],
      [0.77, 0.74],
      [0.43, 0.84],
      [0.55, 0.85],
    ])
      trees(x, y, 16, 0.023);
  } else if (field.id === 'railway') {
    road(0.2, 0.05, 0.065, 0.9);
    road(0.755, 0.05, 0.065, 0.9);
    road(0.05, 0.585, 0.9, 0.085);
    road(0.05, 0.26, 0.9, 0.065);
    decor('rail', 0.345, 0.04, 0.026, 0.92, 0.06);
    decor('rail', 0.63, 0.04, 0.026, 0.92, 0.06);
    for (const x of [0.34, 0.627])
      for (const y of [0.075, 0.15, 0.35, 0.425, 0.7, 0.78])
        add('container', x, y, 0.035, 0.059, 2.8);
    for (const [x, y] of [
      [0.07, 0.37],
      [0.82, 0.47],
      [0.42, 0.7],
      [0.68, 0.13],
    ])
      add('warehouse', x, y, 0.085, 0.1, 4.6);
    add('water', 0.075, 0.75, 0.105, 0.1, 0.04);
    trees(0.83, 0.74, 12);
    trees(0.1, 0.13, 8);
  } else {
    road(0.04, 0.41, 0.92, 0.07);
    road(0.04, 0.57, 0.92, 0.085);
    for (const x of [0.22, 0.5, 0.78]) {
      road(x - 0.023, 0.05, 0.046, 0.9);
      decor('bridge', x - 0.026, 0.475, 0.052, 0.1, 0.1);
    }
    const banks = [
      [0.035, 0.194],
      [0.246, 0.474],
      [0.526, 0.754],
      [0.806, 0.965],
    ];
    for (const [left, right] of banks)
      add('water', left, 0.48, right - left, 0.09, 0.04);
    add('warehouse', 0.3, 0.23, 0.075, 0.07, 4);
    add('office', 0.6, 0.72, 0.065, 0.07, 5.5);
    add('container', 0.855, 0.32, 0.05, 0.025, 2.5);
    trees(0.07, 0.21, 16);
    trees(0.54, 0.29, 12);
    trees(0.3, 0.73, 16);
    trees(0.84, 0.74, 16);
  }
  // Trees belong on land; a trunk cannot be embedded in another solid feature.
  const clearStructures = structures.filter(
    (tree) =>
      tree.kind !== 'tree' ||
      !structures.some(
        (other) =>
          other !== tree &&
          other.kind !== 'tree' &&
          tree.x < other.x + other.w &&
          tree.x + tree.w > other.x &&
          tree.y < other.y + other.h &&
          tree.y + tree.h > other.y,
      ),
  );
  return { roads, structures: clearStructures, decorations };
}
