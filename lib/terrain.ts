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
    | 'boundary';
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
    const steel = !['barrier', 'tree', 'hedge'].includes(kind);
    structures.push({
      x,
      y,
      w,
      h,
      kind,
      height: high,
      steel,
      hp: steel
        ? Infinity
        : kind === 'tree'
          ? 180
          : kind === 'hedge'
            ? 75
            : 130,
      maxHp: steel
        ? Infinity
        : kind === 'tree'
          ? 180
          : kind === 'hedge'
            ? 75
            : 130,
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
        variant === 0 ? 7.6 : 4.2,
      );
      add(
        x + half + gap,
        y,
        half,
        h * 0.72,
        variant === 2 ? 'office' : 'warehouse',
        variant === 2 ? 6.8 : 3.8,
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
