export const MAX_LEVEL = 30;
export const EVOLUTIONS = [
  {
    level: 1,
    name: '新兵战车',
    color: '#829078',
    accent: '#bec9a0',
    detail: '轻量炮塔与基础履带，从第一辆敌车开始。',
  },
  {
    level: 6,
    name: '先锋装甲',
    color: '#6f8876',
    accent: '#a5d0b0',
    detail: '加装侧裙、储物篮与防护板。',
  },
  {
    level: 11,
    name: '破阵主战',
    color: '#647e89',
    accent: '#81d4e3',
    detail: '反应装甲、炮塔护颊与烟幕发射器。',
  },
  {
    level: 16,
    name: '钢铁堡垒',
    color: '#66758d',
    accent: '#a9bbff',
    detail: '分层重甲、前铲与重型炮管护套。',
  },
  {
    level: 21,
    name: '雷霆统帅',
    color: '#958568',
    accent: '#ffd381',
    detail: '战术雷达、主动防护阵列与双侧散热舱。',
  },
  {
    level: 26,
    name: '黎明霸主',
    color: '#b0a17c',
    accent: '#ffe6a2',
    detail: '能量核心、肩部装甲与发光能量导轨。',
  },
  {
    level: 30,
    name: '永恒战神',
    color: '#d0c4a1',
    accent: '#fff1c6',
    detail: '最终装甲冠、环形核心与金色全套装甲。',
  },
] as const;
const TITLES = [
  '旧城新兵',
  '炮手学徒',
  '装甲列兵',
  '履带尖兵',
  '前线战士',
  '轻装先锋',
  '突击中士',
  '猎杀少尉',
  '钢锋中尉',
  '战场上尉',
  '破阵主战',
  '装甲骑士',
  '战术精英',
  '钢铁先锋',
  '王牌车长',
  '钢铁堡垒',
  '重装领主',
  '攻坚大师',
  '前线统领',
  '装甲将军',
  '雷霆统帅',
  '风暴战将',
  '破晓元帅',
  '无畏征服者',
  '苍穹守望',
  '黎明霸主',
  '星火执政',
  '钢铁传奇',
  '终极守护',
  '永恒战神',
];
export function killsForLevel(level: number) {
  const n = Math.max(0, Math.min(MAX_LEVEL - 1, Math.floor(level) - 1));
  return (n * (n + 5)) / 2;
}
export function progression(rawKills: number) {
  const kills = Number.isFinite(rawKills)
    ? Math.max(0, Math.floor(rawKills))
    : 0;
  let level = 1;
  while (level < MAX_LEVEL && kills >= killsForLevel(level + 1)) level++;
  const stage = EVOLUTIONS.reduce(
    (best, e, i) => (level >= e.level ? i : best),
    0,
  );
  const next = level < MAX_LEVEL ? killsForLevel(level + 1) : null;
  const current = killsForLevel(level);
  return {
    kills,
    level,
    stage,
    title: TITLES[level - 1],
    evolution: EVOLUTIONS[stage],
    current,
    next,
    remaining: next === null ? 0 : next - kills,
    progress: next === null ? 1 : (kills - current) / (next - current),
    maxed: level === MAX_LEVEL,
  };
}
export function growthBonus(kills: number) {
  const n = progression(kills).level - 1;
  return {
    hp: 6 * n,
    damage: 1 + 0.035 * n,
    rate: 1 - 0.008 * n,
    speed: n * 1.2,
  };
}
