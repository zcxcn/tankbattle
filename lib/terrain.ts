import { type Battlefield, type TerrainFeature } from './battlefields';
export type Road = { x: number; y: number; w: number; h: number };
export const ARENA_MARGIN = 25;
export const enemyEntrances = (width: number) =>
  [0.22, 0.5, 0.78].map((fraction) => ({ x: width * fraction, y: 110 }));
export type Structure = Road & {
  shape?: 'ellipse';
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
  // Open wilderness has natural cover only. Every pond is shallow enough to ford.
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
  ]) {
    add('hill', x, y, w, h, 11 + ((x * 30) % 4));
    structures[structures.length - 1].shape = 'ellipse';
  }
  for (const [x, y, w, h] of [
    [0.3, 0.48, 0.15, 0.13],
    [0.55, 0.42, 0.14, 0.14],
    [0.17, 0.74, 0.11, 0.13],
  ])
    decorations.push({
      kind: 'water',
      shape: 'ellipse',
      x: x * width,
      y: y * height,
      w: w * width,
      h: h * height,
      height: 0.04,
    });
  trees(0.24, 0.16, 16);
  trees(0.53, 0.77, 16);
  trees(0.81, 0.49, 20);
  trees(0.09, 0.47, 16);
  trees(0.36, 0.18, 12);
  trees(0.69, 0.75, 16);
  trees(0.06, 0.59, 12);
  trees(0.79, 0.18, 16);
  // Trees belong on land; a trunk cannot be embedded in another solid feature.
  const clearStructures = structures.filter(
    (tree) =>
      tree.kind !== 'tree' ||
      ![...structures, ...decorations].some(
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
