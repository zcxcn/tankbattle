import { Battle, W, H, seeded, type Tank } from './engine';
import { CHASSIS, MISSIONS } from './campaign';
export class Renderer {
  canvas: HTMLCanvasElement;
  ctx: CanvasRenderingContext2D;
  terrain: HTMLCanvasElement;
  scale = 1;
  ox = 0;
  oy = 0;
  width = 0;
  height = 0;
  constructor(canvas: HTMLCanvasElement, battle: Battle) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d')!;
    this.terrain = document.createElement('canvas');
    this.terrain.width = W;
    this.terrain.height = H;
    this.createTerrain(battle);
  }
  resize() {
    const r = this.canvas.getBoundingClientRect(),
      dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.width = r.width;
    this.height = r.height;
    this.canvas.width = Math.round(r.width * dpr);
    this.canvas.height = Math.round(r.height * dpr);
    this.scale = Math.min(r.width / W, r.height / H);
    this.ox = (r.width - W * this.scale) / 2;
    this.oy = (r.height - H * this.scale) / 2;
  }
  pointer(x: number, y: number) {
    const r = this.canvas.getBoundingClientRect();
    return {
      x: (x - r.left - this.ox) / this.scale,
      y: (y - r.top - this.oy) / this.scale,
    };
  }
  createTerrain(b: Battle) {
    const c = this.terrain.getContext('2d')!,
      rand = seeded(80 + b.mission);
    c.fillStyle = MISSIONS[b.mission].color;
    c.fillRect(0, 0, W, H);
    for (let y = 0; y < H; y += 64)
      for (let x = 0; x < W; x += 64) {
        c.fillStyle = `rgba(${rand() > 0.5 ? '0,0,0' : '160,160,140'},${rand() * 0.055})`;
        c.fillRect(x + 1, y + 1, 62, 62);
        c.strokeStyle = '#080c091c';
        c.strokeRect(x, y, 64, 64);
      }
    c.fillStyle = '#1119143c';
    c.fillRect(525, 0, 230, H);
    c.fillRect(0, 280, W, 240);
    c.strokeStyle = '#b2b09823';
    c.lineWidth = 2;
    c.setLineDash([24, 24]);
    for (const x of [538, 742]) {
      c.beginPath();
      c.moveTo(x, 30);
      c.lineTo(x, H - 30);
      c.stroke();
    }
    c.setLineDash([]);
    for (let i = 0; i < 6000; i++) {
      const v = rand() > 0.5 ? 130 : 15;
      c.fillStyle = `rgba(${v},${v},${v * 0.85},${rand() * 0.14})`;
      c.fillRect(rand() * W, rand() * H, rand() * 3 + 0.5, rand() * 2 + 0.5);
    }
    for (let i = 0; i < 40; i++) {
      const x = rand() * W,
        y = rand() * H,
        g = c.createRadialGradient(x, y, 1, x, y, rand() * 55 + 15);
      g.addColorStop(0, '#13181055');
      g.addColorStop(1, '#13181000');
      c.fillStyle = g;
      c.fillRect(x - 75, y - 75, 150, 150);
    }
    for (let i = 0; i < 130; i++) {
      const x = rand() * W,
        y = rand() * H;
      c.strokeStyle = '#0e150c44';
      c.lineWidth = 0.8;
      c.beginPath();
      c.moveTo(x, y);
      for (let j = 0; j < 4; j++)
        c.lineTo(x + j * 7 + rand() * 10, y + j * 4 + rand() * 16);
      c.stroke();
    }
    c.strokeStyle = '#a9a48440';
    c.lineWidth = 3;
    c.strokeRect(24, 24, W - 48, H - 48);
    for (let x = 28; x < W - 28; x += 60) {
      c.fillStyle = '#b4a36b44';
      c.fillRect(x, 17, 26, 6);
      c.fillRect(x, H - 23, 26, 6);
    }
    c.font = 'bold 60px monospace';
    c.fillStyle = '#d8d4ac0e';
    c.fillText('SECTOR 0' + (b.mission + 1), 45, H - 70);
    c.font = '12px monospace';
    c.fillStyle = '#d2d3b744';
    c.fillText('DUST BAY / FORWARD OPERATING ZONE', 45, H - 45);
  }
  tank(
    c: CanvasRenderingContext2D,
    t: Tank,
    isPlayer: boolean,
    time: number,
    b: Battle,
  ) {
    c.save();
    c.translate(t.x, t.y);
    if (t.spawn > 0) c.globalAlpha = 0.25 + Math.sin(time * 20) * 0.2;
    c.save();
    c.rotate(t.angle);
    const s = t.radius / 20;
    c.scale(s, s);
    c.shadowColor = '#0008';
    c.shadowBlur = 9;
    c.shadowOffsetX = 5;
    c.shadowOffsetY = 8;
    c.fillStyle = '#111713';
    c.fillRect(-24, -21, 46, 13);
    c.fillRect(-24, 8, 46, 13);
    c.shadowColor = 'transparent';
    for (const y of [-20, 10]) {
      c.fillStyle = '#494d43';
      c.fillRect(-22, y, 43, 9);
      for (let x = -21; x < 22; x += 6) {
        c.fillStyle = '#202720';
        c.fillRect(x, y, 2, 9);
        c.fillStyle = '#626559';
        c.fillRect(x, y, 1, 2);
      }
    }
    const color = isPlayer
      ? CHASSIS[b.save.chassis].color
      : t.kind === 3
        ? '#9f735d'
        : t.kind === 2
          ? '#938779'
          : t.kind === 1
            ? '#aeb096'
            : '#b49678';
    const gradient = c.createLinearGradient(0, -16, 0, 17);
    gradient.addColorStop(0, color);
    gradient.addColorStop(0.35, isPlayer ? '#69794e' : '#715c49');
    gradient.addColorStop(1, isPlayer ? '#3d4b30' : '#44372c');
    c.fillStyle = gradient;
    c.beginPath();
    c.moveTo(-21, -14);
    c.lineTo(14, -14);
    c.lineTo(23, -9);
    c.lineTo(23, 9);
    c.lineTo(14, 14);
    c.lineTo(-21, 14);
    c.closePath();
    c.fill();
    c.strokeStyle = '#e9e5bd44';
    c.lineWidth = 1;
    c.stroke();
    c.fillStyle = '#162013';
    c.fillRect(-18, -8, 12, 16);
    c.fillStyle = '#879476';
    for (let i = 0; i < 5; i++) c.fillRect(-17 + i * 2.5, -7, 1, 14);
    c.strokeStyle = '#192113';
    c.strokeRect(10, -10, 9, 20);
    c.fillStyle = isPlayer ? '#c8d3a1' : '#bb8b6a';
    c.fillRect(13, -11, 6, 3);
    c.fillRect(13, 8, 6, 3);
    c.fillStyle = '#fff3b9';
    c.shadowColor = '#ffdf73';
    c.shadowBlur = 5;
    c.fillRect(21, -10, 2, 3);
    c.fillRect(21, 7, 2, 3);
    c.shadowBlur = 0;
    if (isPlayer) {
      c.fillStyle = '#eee4b2';
      c.fillRect(-4, -14, 5, 3);
      c.fillRect(-4, 11, 5, 3);
    }
    c.restore();
    c.save();
    c.rotate(t.turret);
    c.scale(t.radius / 20, t.radius / 20);
    c.shadowColor = '#0009';
    c.shadowBlur = 4;
    c.shadowOffsetX = 3;
    c.shadowOffsetY = 5;
    c.fillStyle = isPlayer ? '#76815a' : '#887260';
    c.beginPath();
    c.moveTo(-12, -11);
    c.lineTo(6, -11);
    c.lineTo(14, -6);
    c.lineTo(14, 6);
    c.lineTo(6, 11);
    c.lineTo(-12, 11);
    c.closePath();
    c.fill();
    c.strokeStyle = isPlayer ? '#c4c99588' : '#d0b8a388';
    c.stroke();
    c.fillStyle = '#262d21';
    c.fillRect(8, -4, 29, 8);
    c.shadowColor = 'transparent';
    const barrel = c.createLinearGradient(0, -4, 0, 4);
    barrel.addColorStop(0, isPlayer ? '#bec5a1' : '#c9b099');
    barrel.addColorStop(0.5, isPlayer ? '#7e8b65' : '#88745f');
    barrel.addColorStop(1, '#363c2d');
    c.fillStyle = barrel;
    c.fillRect(9, -3, 29, 6);
    c.fillStyle = '#1c251b';
    c.fillRect(33, -4, 7, 8);
    c.fillStyle = isPlayer ? '#aab98b' : '#ae9380';
    c.beginPath();
    c.arc(-5, 0, 5, 0, Math.PI * 2);
    c.fill();
    c.strokeStyle = '#37412c';
    c.stroke();
    c.beginPath();
    c.moveTo(-8, 0);
    c.lineTo(-2, 0);
    c.stroke();
    if (t.flash > 0) {
      c.fillStyle = '#fff0b1';
      c.shadowColor = '#ff9d2d';
      c.shadowBlur = 22;
      c.beginPath();
      c.moveTo(37, -4);
      c.lineTo(55, -10);
      c.lineTo(50, 0);
      c.lineTo(57, 8);
      c.lineTo(37, 4);
      c.closePath();
      c.fill();
    }
    c.restore();
    if (isPlayer) {
      c.strokeStyle = '#dceba288';
      c.lineWidth = 1.2;
      c.setLineDash([6, 5]);
      c.beginPath();
      c.arc(0, 0, t.radius + 12, 0, Math.PI * 2);
      c.stroke();
      c.setLineDash([]);
      if (b.shield > 0.3) {
        c.shadowColor = '#98e6cf';
        c.shadowBlur = 16;
        c.strokeStyle = '#a4f5df99';
        c.lineWidth = 2;
        c.beginPath();
        c.arc(0, 0, 31 + Math.sin(time * 8) * 2, 0, Math.PI * 2);
        c.stroke();
      }
    } else if (t.spawn <= 0) {
      c.fillStyle = '#111710b0';
      c.fillRect(-23, -t.radius - 15, 46, 4);
      c.fillStyle =
        t.stun > 0 ? '#8adeeb' : t.kind === 3 ? '#fa9660' : '#d39068';
      c.fillRect(-23, -t.radius - 15, (46 * t.hp) / t.maxHp, 4);
      if (t.cooldown < 0.4 && t.stun <= 0) {
        c.strokeStyle = '#ffb578';
        c.lineWidth = 1;
        c.beginPath();
        c.arc(0, 0, t.radius + 7, 0, Math.PI * 2);
        c.stroke();
      }
    }
    if (t.stun > 0) {
      c.strokeStyle = '#9fe5f9';
      c.shadowColor = '#69d5ee';
      c.shadowBlur = 8;
      c.beginPath();
      c.moveTo(-7, -7);
      c.lineTo(3, -13);
      c.lineTo(-2, -2);
      c.lineTo(8, -7);
      c.stroke();
    }
    c.restore();
  }
  draw(b: Battle, aim: { x: number; y: number } | null) {
    const c = this.ctx,
      dpr = Math.min(window.devicePixelRatio || 1, 2);
    c.setTransform(dpr, 0, 0, dpr, 0, 0);
    c.fillStyle = '#0c100e';
    c.fillRect(0, 0, this.width, this.height);
    if (this.width / this.height < 1.2) {
      this.scale = Math.max(this.width / 760, this.height / H);
      this.ox = Math.min(
        0,
        Math.max(
          this.width - W * this.scale,
          this.width / 2 - b.player.x * this.scale,
        ),
      );
      this.oy = Math.min(
        0,
        Math.max(
          this.height - H * this.scale,
          this.height / 2 - b.player.y * this.scale,
        ),
      );
    }
    c.save();
    c.translate(this.ox, this.oy);
    c.scale(this.scale, this.scale);
    if (b.save.shake && b.shake > 0)
      c.translate(
        Math.sin(b.elapsed * 151) * b.shake,
        Math.cos(b.elapsed * 127) * b.shake * 0.6,
      );
    c.drawImage(this.terrain, 0, 0);
    for (const t of b.tracks) {
      c.save();
      c.translate(t.x, t.y);
      c.rotate(t.angle);
      c.fillStyle = `rgba(5,10,5,${t.life / 35})`;
      c.fillRect(-4, -23, 8, 7);
      c.fillRect(-4, 16, 8, 7);
      c.restore();
    }
    for (const s of b.scars) {
      const g = c.createRadialGradient(s.x, s.y, 0, s.x, s.y, s.r);
      g.addColorStop(0, '#080c0bd9');
      g.addColorStop(0.65, '#171a13aa');
      g.addColorStop(1, '#131a1300');
      c.fillStyle = g;
      c.fillRect(s.x - s.r, s.y - s.r, s.r * 2, s.r * 2);
    }
    for (const w of b.walls) {
      if (w.hp <= 0) {
        c.fillStyle = '#80775e';
        for (let i = 0; i < 8; i++)
          c.fillRect(
            w.x + ((i * 47) % w.w),
            w.y + ((i * 19) % w.h),
            7 + (i % 4),
            5 + (i % 5),
          );
        continue;
      }
      c.shadowColor = '#070d09a0';
      c.shadowBlur = 7;
      c.shadowOffsetX = 8;
      c.shadowOffsetY = 12;
      c.fillStyle = w.steel ? '#444b44' : '#736b53';
      c.fillRect(w.x, w.y, w.w, w.h);
      c.shadowColor = 'transparent';
      c.fillStyle = w.steel ? '#788277' : '#aaa18a';
      c.fillRect(w.x, w.y, w.w, 5);
      c.fillStyle = w.steel ? '#30372f' : '#514931';
      c.fillRect(w.x, w.y + w.h - 6, w.w, 6);
      c.strokeStyle = w.steel ? '#222b24' : '#403a2b';
      c.lineWidth = 2;
      c.strokeRect(w.x, w.y, w.w, w.h);
      if (w.steel) {
        for (let x = w.x + 14; x < w.x + w.w - 6; x += 22) {
          c.fillStyle = '#969b8788';
          c.fillRect(x, w.y + 10, 3, 3);
          c.fillRect(x, w.y + w.h - 12, 3, 3);
        }
        for (let y = w.y + 19; y < w.y + w.h - 10; y += 15) {
          c.strokeStyle = '#252d2566';
          c.beginPath();
          c.moveTo(w.x + 6, y);
          c.lineTo(w.x + w.w - 6, y);
          c.stroke();
        }
      } else {
        c.strokeStyle = '#49442f99';
        for (let y = w.y + 14; y < w.y + w.h; y += 14) {
          c.beginPath();
          c.moveTo(w.x, y);
          c.lineTo(w.x + w.w, y);
          c.stroke();
          for (
            let x = w.x + ((y - w.y) % 28 === 0 ? 14 : 28);
            x < w.x + w.w;
            x += 28
          ) {
            c.beginPath();
            c.moveTo(x, y - 14);
            c.lineTo(x, y);
            c.stroke();
          }
        }
        if (w.hp < 70) {
          c.strokeStyle = '#232719';
          c.lineWidth = 2;
          c.beginPath();
          c.moveTo(w.x + w.w * 0.6, w.y);
          c.lineTo(w.x + w.w * 0.42, w.y + w.h * 0.4);
          c.lineTo(w.x + w.w * 0.6, w.y + w.h * 0.55);
          c.lineTo(w.x + w.w * 0.4, w.y + w.h);
          c.stroke();
        }
      }
    }
    if (b.isDefend) {
      const p = b.base;
      c.save();
      c.translate(p.x, p.y);
      c.strokeStyle = '#abdcb955';
      c.lineWidth = 2;
      c.beginPath();
      c.arc(0, 0, 40 + Math.sin(b.elapsed * 3) * 5, 0, Math.PI * 2);
      c.stroke();
      c.fillStyle = '#414d3a';
      c.fillRect(-24, -24, 48, 48);
      c.strokeStyle = '#b5d8a0';
      c.strokeRect(-24, -24, 48, 48);
      c.fillStyle = '#aacba1';
      c.fillRect(-3, -14, 6, 28);
      c.fillRect(-14, -3, 28, 6);
      c.fillStyle = '#142011';
      c.fillRect(-35, 34, 70, 6);
      c.fillStyle = '#aad297';
      c.fillRect(-35, 34, (70 * p.hp) / p.maxHp, 6);
      c.fillStyle = '#d8eacb';
      c.font = '11px sans-serif';
      c.textAlign = 'center';
      c.fillText('撤离信标', 0, 57);
      c.restore();
    }
    for (const item of b.pickups) {
      c.save();
      c.translate(item.x, item.y + Math.sin(b.elapsed * 4) * 3);
      c.rotate(Math.PI / 4);
      c.shadowColor = ['#ade4ab', '#ffd686', '#99eaf2'][item.kind];
      c.shadowBlur = 16;
      c.fillStyle = '#243a29';
      c.strokeStyle = ['#ade4ab', '#ffd686', '#99eaf2'][item.kind];
      c.fillRect(-12, -12, 24, 24);
      c.strokeRect(-12, -12, 24, 24);
      c.rotate(-Math.PI / 4);
      c.shadowBlur = 0;
      c.fillStyle = c.strokeStyle;
      c.textAlign = 'center';
      c.textBaseline = 'middle';
      c.font = 'bold 19px sans-serif';
      c.fillText(['+', '»', '◇'][item.kind], 0, 0);
      c.restore();
    }
    for (const e of b.enemies) this.tank(c, e, false, b.elapsed, b);
    this.tank(c, b.player, true, b.elapsed, b);
    for (const bullet of b.bullets) {
      c.save();
      c.strokeStyle = bullet.enemy ? '#ff9b62' : '#ffe2a3';
      c.shadowColor = bullet.enemy ? '#ff6926' : '#ffc73b';
      c.shadowBlur = 13;
      c.lineWidth = bullet.enemy ? 4 : 3;
      c.lineCap = 'round';
      const len = Math.hypot(bullet.vx, bullet.vy);
      c.beginPath();
      c.moveTo(
        bullet.x - (bullet.vx / len) * 15,
        bullet.y - (bullet.vy / len) * 15,
      );
      c.lineTo(bullet.x, bullet.y);
      c.stroke();
      c.fillStyle = '#fff6dc';
      c.beginPath();
      c.arc(bullet.x, bullet.y, 2.1, 0, Math.PI * 2);
      c.fill();
      c.restore();
    }
    for (const p of b.particles) {
      c.save();
      c.globalAlpha = p.life / p.max;
      c.fillStyle = p.color;
      if (p.smoke) {
        c.beginPath();
        c.arc(p.x, p.y, p.size * (2 - p.life / p.max), 0, Math.PI * 2);
        c.fill();
      } else {
        c.shadowColor = p.color;
        c.shadowBlur = 9;
        c.fillRect(p.x, p.y, p.size, p.size);
      }
      c.restore();
    }
    if (b.pulse > 0) {
      c.save();
      c.strokeStyle = `rgba(132,231,244,${b.pulse})`;
      c.lineWidth = 4 * b.pulse;
      c.shadowColor = '#95e9f1';
      c.shadowBlur = 20;
      c.beginPath();
      c.arc(b.player.x, b.player.y, (1 - b.pulse) * 310, 0, Math.PI * 2);
      c.stroke();
      c.restore();
    }
    if (aim) {
      c.save();
      c.translate(aim.x, aim.y);
      c.strokeStyle = '#e6e6c999';
      c.lineWidth = 1.2;
      c.beginPath();
      c.arc(0, 0, 10, 0, Math.PI * 2);
      for (const [x, y, x2, y2] of [
        [-17, 0, -7, 0],
        [7, 0, 17, 0],
        [0, -17, 0, -7],
        [0, 7, 0, 17],
      ]) {
        c.moveTo(x, y);
        c.lineTo(x2, y2);
      }
      c.stroke();
      c.restore();
    }
    const vignette = c.createRadialGradient(
      W / 2,
      H / 2,
      280,
      W / 2,
      H / 2,
      760,
    );
    vignette.addColorStop(0, '#07100c00');
    vignette.addColorStop(1, '#07100c88');
    c.fillStyle = vignette;
    c.fillRect(0, 0, W, H);
    for (let i = 0; i < 22; i++) {
      const x = (i * 137 + b.elapsed * (7 + (i % 3))) % W,
        y = (i * 79 - b.elapsed * (9 + (i % 5)) + H * 10) % H;
      c.fillStyle = `rgba(234,190,102,${0.15 + Math.sin(b.elapsed + i) * 0.1})`;
      c.fillRect(x, y, 1.5, 1.5);
    }
    c.restore();
  }
}
