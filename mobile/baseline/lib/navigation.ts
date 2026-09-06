type Point = { x: number; y: number };
/** Shared reverse flood fields: an entire enemy group reuses one route to each target. */
export class StreetNavigation {
  private step = 32;
  private cols: number;
  private rows: number;
  private grids = new Map<number, Uint8Array>();
  private fields = new Map<string, Int16Array>();
  private revision = -1;
  constructor(
    width: number,
    height: number,
    private free: (x: number, y: number, radius: number) => boolean,
  ) {
    this.cols = Math.ceil(width / this.step);
    this.rows = Math.ceil(height / this.step);
  }
  private point(index: number) {
    return {
      x: ((index % this.cols) + 0.5) * this.step,
      y: (Math.floor(index / this.cols) + 0.5) * this.step,
    };
  }
  guide(
    from: Point,
    target: Point,
    radius: number,
    revision: number,
  ): Point | null {
    if (revision !== this.revision) {
      this.grids.clear();
      this.fields.clear();
      this.revision = revision;
    }
    const r = radius > 26 ? 46 : 26;
    let grid = this.grids.get(r);
    if (!grid) {
      grid = new Uint8Array(this.cols * this.rows);
      for (let i = 0; i < grid.length; i++) {
        const p = this.point(i);
        grid[i] = this.free(p.x, p.y, r + 2) ? 1 : 0;
      }
      this.grids.set(r, grid);
    }
    const nearest = (p: Point) => {
      const cx = Math.floor(p.x / this.step),
        cy = Math.floor(p.y / this.step);
      let best = -1,
        distance = Infinity;
      for (
        let y = Math.max(0, cy - 3);
        y <= Math.min(this.rows - 1, cy + 3);
        y++
      )
        for (
          let x = Math.max(0, cx - 3);
          x <= Math.min(this.cols - 1, cx + 3);
          x++
        ) {
          const index = y * this.cols + x,
            q = this.point(index);
          const d = Math.hypot(q.x - p.x, q.y - p.y);
          if (grid![index] && d < distance) {
            best = index;
            distance = d;
          }
        }
      return best;
    };
    const goal = nearest(target),
      start = nearest(from);
    if (goal < 0 || start < 0) return null;
    const key = `${r}:${goal}`;
    let field = this.fields.get(key);
    if (!field) {
      // Limit memory when targets cross many cells; immutable geometry masks stay cached.
      if (this.fields.size >= 12) this.fields.clear();
      field = new Int16Array(grid.length).fill(-1);
      const queue = new Int16Array(grid.length);
      let head = 0,
        tail = 1;
      queue[0] = goal;
      field[goal] = 0;
      while (head < tail) {
        const current = queue[head++];
        for (const next of this.neighbors(current))
          if (grid[next] && field[next] < 0) {
            field[next] = field[current] + 1;
            queue[tail++] = next;
          }
      }
      this.fields.set(key, field);
    }
    if (field[start] < 0) return null;
    const center = this.point(start);
    // Get onto the corridor before taking a turn; never cut a building corner.
    if (Math.hypot(center.x - from.x, center.y - from.y) > this.step * 0.6)
      return center;
    let next = start;
    for (const n of this.neighbors(start))
      if (field[n] >= 0 && field[n] < field[next]) next = n;
    return this.point(next);
  }
  private neighbors(index: number) {
    const values: number[] = [],
      x = index % this.cols;
    if (x > 0) values.push(index - 1);
    if (x < this.cols - 1) values.push(index + 1);
    if (index >= this.cols) values.push(index - this.cols);
    if (index < this.cols * (this.rows - 1)) values.push(index + this.cols);
    return values;
  }
}
