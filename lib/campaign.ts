import { growthBonus } from './progression';
export const MISSIONS = [
  {
    name: '灰中点火',
    location: '黄昏修理厂',
    type: 'assault',
    tag: '突击',
    count: 6,
    duration: 0,
    color: '#3b4030',
    brief:
      '军团封死了修理厂，城里只剩你这台坦克还能开。清掉路口，接回最后一支撤离队。',
    quote: '发动机还响着，尘湾就还没输。',
    end: '路口清空。黎雁的电台亮了起来：撤离车队需要我们，去盐桥！',
    objective: '突破封锁，歼灭 6 辆敌军坦克',
  },
  {
    name: '盐桥守夜',
    location: '盐桥河岸',
    type: 'defend',
    tag: '防守',
    count: 9,
    duration: 45,
    color: '#2d3c40',
    brief:
      '撤离车队正在过桥，桥头信标会引导他们穿过烟雾。守住它，直到最后一辆车离开。',
    quote: '别让那些灯熄灭。',
    end: '最后一辆车过桥了。那些灯，是我们救下来的人。',
    objective: '保护撤离信标，坚持 45 秒',
  },
  {
    name: '断轨行动',
    location: '废弃货场',
    type: 'assault',
    tag: '突击',
    count: 10,
    duration: 0,
    color: '#44392b',
    brief:
      '巨型战车“天炉”正沿运煤铁路向城中心推进。截断货场的补给线，让这头钢铁巨兽停下来。',
    quote: '打掉它的补给，它也会害怕熄火。',
    end: '补给线已切断。但地下车站还有人……黎雁的声音突然变得急促。',
    objective: '切断补给，歼灭 10 辆敌军坦克',
  },
  {
    name: '最后一班',
    location: '旧城地下车站',
    type: 'defend',
    tag: '防守',
    count: 14,
    duration: 60,
    color: '#383a31',
    brief:
      '地下车站还困着一批居民，黎雁正在带他们登车。守住车站电源，这一次，谁都不能掉队。',
    quote: '最后一班车，不会丢下任何人。',
    end: '车厢坐满了……我也上车了。现在，轮到我们回头。',
    objective: '保护车站电源，坚持 60 秒',
  },
  {
    name: '黑炉破晓',
    location: '北部铸造厂',
    type: 'assault',
    tag: '突击',
    count: 14,
    duration: 0,
    color: '#373037',
    brief:
      '天炉停在北部铸造厂，残余卫队正为它重新充能。撕开防线，别给它第二次启动的机会。',
    quote: '再向前一步，就是黎明。',
    end: '外围清空。眼前的重型闸门缓缓打开，天炉的引擎正在轰鸣。',
    objective: '突破卫队，歼灭 14 辆敌军坦克',
  },
  {
    name: '余烬之心',
    location: '炉心广场',
    type: 'boss',
    tag: '决战',
    count: 1,
    duration: 0,
    color: '#402f29',
    brief:
      '天炉已经醒了，炮口正转向撤离列车。把它留在这里，让这场漫长的夜结束。',
    quote: '没有退路。只有黎明。',
    end: '“收到你的信号了。”黎雁说。天炉化为余烬，晨光落在尘湾的屋顶。那些被你守护的人们，终于等到了回家的列车。天亮了，指挥官。',
    objective: '击毁巨型战车「天炉」',
  },
  {
    name: '迷雾中继',
    location: '东部通信高地',
    type: 'capture',
    tag: '夺点',
    count: 18,
    duration: 0,
    color: '#2d3c40',
    brief:
      '夺回三座中继站，把失联的避难所重新接入电台。靠近站点完成接管，敌军进入范围会中断进度。',
    quote: '灯亮一盏，就多一条回家的路。',
    end: '三个频道同时传来回答。原来，这座城从未孤军奋战。',
    objective: '占领 3 座中继站，每座驻守 8 秒',
  },
  {
    name: '长路归人',
    location: '环城疏散公路',
    type: 'escort',
    tag: '护送',
    count: 22,
    duration: 0,
    color: '#44392b',
    brief:
      '一辆满载伤员的运输车无法独自穿越封锁。保持在它周围，清除路线上的军团猎兵。',
    quote: '慢一点也没关系，把所有人带回来。',
    end: '运输车驶进医疗营。黎雁说，下一步该找出军团的指挥中心。',
    objective: '伴随运输车穿越 5 个路标，保护车体',
  },
  {
    name: '无声档案',
    location: '沉没的资料库',
    type: 'extract',
    tag: '回收',
    count: 20,
    duration: 0,
    color: '#373037',
    brief:
      '三份撤离名单散落在旧资料库。回收档案，再回到南侧接应点，不能让名单落入敌手。',
    quote: '纸上每个名字，都在等一个回答。',
    end: '名单安全送达，其中藏着军团燃料网络的坐标。',
    objective: '回收 3 份情报，再返回南侧撤离点',
  },
  {
    name: '断流时刻',
    location: '赤砂燃料基地',
    type: 'sabotage',
    tag: '破坏',
    count: 24,
    duration: 0,
    color: '#402f29',
    brief:
      '军团把燃料泵连成了防御网络。轰毁三座储能设施，维修车会不断修复它们的护卫。',
    quote: '没有燃料，再厚的装甲也只是废铁。',
    end: '燃料网络瘫痪。军团的火箭阵地却转向了医疗营。',
    objective: '用炮火摧毁 3 座燃料设施',
  },
  {
    name: '白线坚守',
    location: '北境野战医院',
    type: 'defend',
    tag: '防守',
    count: 24,
    duration: 90,
    color: '#383a31',
    brief:
      '医疗营正在转移最后一批伤员。火箭车将从侧翼进攻，狙击车在远处等你离开掩体。',
    quote: '白线之后，是我们守护的人。',
    end: '伤员全部转移，敌方指挥车的信号也暴露了。',
    objective: '保护医疗信标，坚持 90 秒',
  },
  {
    name: '雷暴将至',
    location: '天线阵列',
    type: 'boss',
    tag: '决战',
    count: 1,
    duration: 0,
    color: '#3b4030',
    brief:
      '军团指挥车“雷暴”接管了天线阵列。它会在装甲受损时召来护卫，用密集火力封锁退路。',
    quote: '切断命令，钢铁也会迷路。',
    end: '雷暴的天线折断了。但一个来自海岸的旧频率，仍在呼叫军团。',
    objective: '击毁指挥重坦「雷暴」',
  },
  {
    name: '潮汐回声',
    location: '海岸雷达站',
    type: 'capture',
    tag: '夺点',
    count: 26,
    duration: 0,
    color: '#2d3c40',
    brief: '海岸雷达指向一座无人灯塔。夺回三处雷达节点，拼出藏在潮声里的坐标。',
    quote: '听见海了吗？那是出口。',
    end: '坐标指向黑港。失踪的工程队还在那里。',
    objective: '占领 3 处雷达节点，每处驻守 8 秒',
  },
  {
    name: '黑港渡火',
    location: '港口货运通道',
    type: 'escort',
    tag: '护送',
    count: 28,
    duration: 0,
    color: '#44392b',
    brief: '工程队修好了装甲运输车。为他们开路，带着关闭核心的密钥离开港口。',
    quote: '这次换我们，把修车的人带回家。',
    end: '工程队抵达接应点。核心位置被拆成了三组加密坐标。',
    objective: '护送工程运输车抵达北侧接应点',
  },
  {
    name: '深井密钥',
    location: '废弃矿井外围',
    type: 'extract',
    tag: '回收',
    count: 28,
    duration: 0,
    color: '#373037',
    brief:
      '三个矿井入口保存着最后的坐标。轻型自爆车巡游在窄道里，先观察雷达，再决定路线。',
    quote: '黑暗里走过的每一步，都算数。',
    end: '坐标合并完成。黎雁第一次听见了核心的心跳。',
    objective: '回收 3 枚密钥并安全撤离',
  },
  {
    name: '熄灭群星',
    location: '高压输电场',
    type: 'sabotage',
    tag: '破坏',
    count: 30,
    duration: 0,
    color: '#402f29',
    brief: '核心的三座外置供能塔仍在运转。摧毁供能塔，防住维修编队与火箭齐射。',
    quote: '让那些错误的星星，熄灭吧。',
    end: '三座塔依次熄灭。城里最后一支军团部队正在退守核心。',
    objective: '摧毁 3 座供能塔，切断核心护盾',
  },
  {
    name: '黎明走廊',
    location: '中央防御环',
    type: 'assault',
    tag: '突击',
    count: 26,
    duration: 0,
    color: '#383a31',
    brief:
      '军团把所有剩余装甲推上了最后的走廊。更换适合的主炮和支援模块，一层层拆开这道防线。',
    quote: '身后是整座城，前面只有一扇门。',
    end: '大门打开了。电台里，所有曾经被救下的频道同时回应：我们在。',
    objective: '歼灭 26 辆混合装甲，突破中央防线',
  },
  {
    name: '不灭黎明',
    location: '核心控制庭院',
    type: 'boss',
    tag: '终局',
    count: 1,
    duration: 0,
    color: '#3b4030',
    brief:
      '最后的核心战车“永夜”已经锁定城市电网。它拥有更厚装甲与五联炮，黎雁会陪你到最后一秒。',
    quote: '你不是最后一辆坦克。你是第一个回家的人。',
    end: '永夜停机。十八段电台录音，十八次没有放弃。晨光越过海岸，尘湾的每一扇窗都亮了起来。欢迎回家，指挥官。',
    objective: '击毁核心战车「永夜」，结束军团控制',
  },
] as const;
export const CHASSIS = [
  {
    name: '游隼',
    model: 'R-02',
    role: '高速侦察坦克',
    hp: 100,
    speed: 230,
    damage: 23,
    rate: 0.34,
    color: '#b3c2ac',
    desc: '快速转移，以机动换取生存。',
    stats: [46, 95, 60],
  },
  {
    name: '灰狼',
    model: 'M-04',
    role: '均衡型主战坦克',
    hp: 150,
    speed: 180,
    damage: 32,
    rate: 0.46,
    color: '#b8be83',
    desc: '可靠的中型底盘，适应任何战场。',
    stats: [70, 73, 76],
  },
  {
    name: '磐石',
    model: 'H-09',
    role: '重装攻坚坦克',
    hp: 230,
    speed: 135,
    damage: 48,
    rate: 0.68,
    color: '#bbb59c',
    desc: '厚重装甲与重炮，正面突破防线。',
    stats: [100, 45, 100],
  },
] as const;
export const UPGRADES = [
  { name: '复合装甲', desc: '每级最大生命 +25', icon: 'shield' },
  { name: '穿甲弹芯', desc: '每级主炮伤害 +6', icon: 'target' },
  { name: '自动装填', desc: '每级射击间隔缩短 10%', icon: 'reload' },
  { name: '高扭履带', desc: '每级移动速度 +15', icon: 'speed' },
  { name: '增压炮管', desc: '每级炮弹速度 +90', icon: 'bolt' },
  { name: '战场回收', desc: '每级击毁敌车恢复 4 生命', icon: 'heart' },
];
export const WEAPONS = [
  {
    name: '猎隼加农炮',
    features: '无限弹药 · 均衡直射',
    color: '#ffd57a',
    supply: 0,
    capacity: 0,
    role: '均衡单发',
    desc: '稳定弹道与标准装填，适合各种距离。',
    damage: 1,
    rate: 1,
    speed: 1,
    spread: [0],
    splash: 0,
    pierce: 0,
    slow: 0,
  },
  {
    name: '蜂群重机枪',
    features: '低伤高频 · 轻甲压制',
    color: '#ff824b',
    supply: 90,
    capacity: 270,
    role: '高速压制',
    desc: '单发伤害 20%，装填时间 28%；适合扫射残血轻型敌军，重甲目标建议换炮。',
    damage: 0.2,
    rate: 0.28,
    speed: 1.2,
    spread: [0],
    splash: 0,
    pierce: 0,
    slow: 0,
  },
  {
    name: '碎星霰弹炮',
    features: '5 弹扇射 · 近距爆发',
    color: '#f5eee1',
    supply: 14,
    capacity: 42,
    role: '近距扇射',
    desc: '一次发射 5 枚弹丸，每枚伤害 42%，射程较短。',
    damage: 0.42,
    rate: 1.55,
    speed: 0.85,
    spread: [-0.22, -0.11, 0, 0.11, 0.22],
    splash: 0,
    pierce: 0,
    slow: 0,
  },
  {
    name: '长弓磁轨炮',
    features: '贯穿 3 车 · 高速重击',
    color: '#b995ff',
    supply: 7,
    capacity: 21,
    role: '高速贯穿',
    desc: '伤害 170%，装填时间 180%，可贯穿 3 辆敌车。',
    damage: 1.7,
    rate: 1.8,
    speed: 2.1,
    spread: [0],
    splash: 0,
    pierce: 2,
    slow: 0,
  },
  {
    name: '熔岩榴弹炮',
    features: '范围爆破 · 掩体拦截',
    color: '#ffa333',
    supply: 8,
    capacity: 24,
    role: '范围爆破',
    desc: '伤害 120%，装填时间 170%，爆炸伤及周围敌军。',
    damage: 1.2,
    rate: 1.7,
    speed: 0.8,
    spread: [0],
    splash: 105,
    pierce: 0,
    slow: 0,
  },
  {
    name: '霜线脉冲炮',
    features: '减速 60% · 持续 2 秒',
    color: '#55e8ff',
    supply: 20,
    capacity: 60,
    role: '减速控制',
    desc: '伤害 75%，命中使敌军移动速度降低 60%，持续 2 秒。',
    damage: 0.75,
    rate: 0.85,
    speed: 1.15,
    spread: [0],
    splash: 0,
    pierce: 0,
    slow: 2,
  },
  {
    name: '天火制导火箭炮',
    features: '自动追踪 · 范围爆破',
    color: '#ff6851',
    supply: 5,
    capacity: 15,
    role: '追踪爆破',
    desc: '伤害 210%，装填时间 260%；锁定前方可见敌车，命中造成范围爆炸。无目标时直射。',
    damage: 2.1,
    rate: 2.6,
    speed: 0.75,
    spread: [0],
    splash: 120,
    pierce: 0,
    slow: 0,
  },
] as const;
export const SUPPORTS = [
  { name: '应急维修', desc: '立即恢复 65 点装甲，冷却 20 秒。', cooldown: 20 },
  { name: '棱镜护盾', desc: '获得 4 秒无敌护盾，冷却 22 秒。', cooldown: 22 },
  {
    name: '制导火箭',
    desc: '最多向 3 个可见敌人各发射一枚 85 伤害火箭，共用火箭弹药，冷却 16 秒。',
    cooldown: 16,
  },
] as const;
export const MODULES = [
  { name: '标准总成', desc: '原装底盘，保持均衡参数。' },
  { name: '堡垒装甲', desc: '最大装甲 +60，移动速度降低 10%。' },
  { name: '涡轮驱动', desc: '移动速度增加 20%，最大装甲降低 20。' },
  {
    name: '回收磁场',
    desc: '补给拾取半径扩大到 140，击毁敌车额外恢复 3 装甲。',
  },
] as const;
export const ENEMIES = [
  { name: '军团步战车', desc: '直线推进，保持距离进行炮击。' },
  { name: '猎犬侦察车', desc: '高速接近，以低伤高频机枪压制，装甲薄弱。' },
  { name: '重炮突击车', desc: '厚甲慢速，橙色榴弹造成范围爆炸。' },
  { name: '指挥巨型战车', desc: '多联炮、分阶段增援；每幕决战都有更强版本。' },
  { name: '堡垒护卫', desc: '正面护甲减伤，近距离发射霰弹；绕后打击。' },
  { name: '幽灵狙击车', desc: '远距锁定，发射高速穿甲弹；注意红色瞄准线。' },
  { name: '烈蜂自爆车', desc: '迅速接近目标并自爆，保持距离提前击毁。' },
  { name: '织补维修车', desc: '修复友军并发射冰蓝脉冲，命中减速；优先击毁。' },
  { name: '风暴火箭车', desc: '扇形齐射爆炸弹，装填间隔较长。' },
] as const;
export function bossName(mission: number) {
  return (
    [
      '铁牙',
      '灰烬哨兵',
      '裂甲者',
      '荒原重锤',
      '熔铁卫士',
      '天炉',
      '黑曜前锋',
      '雷鸣猎手',
      '赤砂暴君',
      '断路者',
      '风暴壁垒',
      '雷暴',
      '暮光执行者',
      '暗铁统领',
      '深渊重炮',
      '终焉堡垒',
      '黎明审判',
      '永夜',
    ][mission] ?? '钢铁统帅'
  );
}
export function loadoutStats(
  save: Save,
  kills = save.kills,
  weapon = save.weapon,
) {
  const growth = growthBonus(kills);
  const c = CHASSIS[save.chassis],
    w = WEAPONS[weapon];
  return {
    hp:
      c.hp +
      save.upgrades[0] * 25 +
      (save.module === 1 ? 60 : save.module === 2 ? -20 : 0) +
      growth.hp,
    speed:
      (c.speed + save.upgrades[3] * 15 + growth.speed) *
      (save.module === 1 ? 0.9 : save.module === 2 ? 1.2 : 1),
    damage: (c.damage + save.upgrades[1] * 6) * w.damage * growth.damage,
    rate: c.rate * Math.pow(0.9, save.upgrades[2]) * w.rate * growth.rate,
  };
}
export type Save = {
  activeRun: { id: string; creditedKills: number; settled: boolean } | null;
  weapon: number;
  support: number;
  module: number;
  completed: number[];
  points: number;
  upgrades: number[];
  chassis: number;
  difficulty: number;
  best: number;
  kills: number;
  sound: boolean;
  music: boolean;
  musicVolume: number;
  musicTrack: number;
  shake: boolean;
  quality: 'cinematic' | 'balanced' | 'performance';
  fps: 30 | 45 | 60;
  resolution: 'adaptive' | 'sharp' | 'ultra';
  mobileConfigured: boolean;
};
export const defaultSave: Save = {
  activeRun: null,
  weapon: 0,
  support: 0,
  module: 0,
  completed: [],
  points: 0,
  upgrades: [0, 0, 0, 0, 0, 0],
  chassis: 1,
  difficulty: 1,
  best: 0,
  kills: 0,
  sound: true,
  music: true,
  musicVolume: 40,
  musicTrack: 0,
  shake: true,
  quality: 'balanced',
  fps: 60,
  resolution: 'sharp',
  mobileConfigured: false,
};
export const SAVE_KEY = 'iron-embers-save-v1';
export function parseSave(raw: string | null): Save {
  if (!raw)
    return {
      ...defaultSave,
      upgrades: [...defaultSave.upgrades],
      completed: [],
    };
  try {
    const d = JSON.parse(raw);
    const int = (v: unknown, min: number, max: number, fallback: number) =>
      typeof v === 'number' && Number.isInteger(v) && v >= min && v <= max
        ? v
        : fallback;
    return {
      activeRun:
        d.activeRun &&
        typeof d.activeRun.id === 'string' &&
        d.activeRun.id.length > 0 &&
        d.activeRun.id.length <= 100
          ? {
              id: d.activeRun.id,
              creditedKills: int(d.activeRun.creditedKills, 0, 1e9, 0),
              settled: d.activeRun.settled === true,
            }
          : null,
      completed: Array.isArray(d.completed)
        ? [
            ...new Set<number>(
              d.completed.filter(
                (v: unknown) =>
                  typeof v === 'number' &&
                  Number.isInteger(v) &&
                  v >= 0 &&
                  v < MISSIONS.length,
              ),
            ),
          ]
        : [],
      weapon: int(d.weapon, 0, WEAPONS.length - 1, 0),
      support: int(d.support, 0, SUPPORTS.length - 1, 0),
      module: int(d.module, 0, MODULES.length - 1, 0),
      points: int(d.points, 0, 1000, 0),
      upgrades: defaultSave.upgrades.map((_, i) =>
        int(d.upgrades?.[i], 0, 3, 0),
      ),
      chassis: int(d.chassis, 0, 2, 1),
      difficulty: int(d.difficulty, 0, 2, 1),
      best: int(d.best, 0, 1e9, 0),
      kills: int(d.kills, 0, 1e9, 0),
      sound: typeof d.sound === 'boolean' ? d.sound : true,
      music: typeof d.music === 'boolean' ? d.music : d.sound !== false,
      musicVolume: int(d.musicVolume, 0, 100, 40),
      musicTrack: int(d.musicTrack, 0, 2, 0),
      shake: typeof d.shake === 'boolean' ? d.shake : true,
      fps: [30, 45, 60].includes(d.fps) ? d.fps : 60,
      resolution: ['adaptive', 'sharp', 'ultra'].includes(d.resolution)
        ? d.resolution
        : 'sharp',
      mobileConfigured: d.mobileConfigured === true,
      quality: ['cinematic', 'balanced', 'performance'].includes(d.quality)
        ? d.quality
        : 'balanced',
    };
  } catch {
    return {
      ...defaultSave,
      upgrades: [...defaultSave.upgrades],
      completed: [],
    };
  }
}

/** Cumulative reports are idempotent; late callbacks from an earlier battle are ignored. */
export function beginRun(save: Save, id: string): Save {
  return { ...save, activeRun: { id, creditedKills: 0, settled: false } };
}
export function creditRunKills(save: Save, id: string, kills: number): Save {
  const run = save.activeRun;
  if (
    !run ||
    run.id !== id ||
    run.settled ||
    !Number.isSafeInteger(kills) ||
    kills < 0 ||
    kills > 1e9 ||
    kills <= run.creditedKills
  )
    return save;
  return {
    ...save,
    kills: Math.min(1e9, save.kills + kills - run.creditedKills),
    activeRun: { ...run, creditedKills: kills },
  };
}
export function settleRun(
  save: Save,
  result: {
    runId: string;
    kills: number;
    mission: number;
    won: boolean;
    endless: boolean;
    score: number;
  },
) {
  if (
    !save.activeRun ||
    save.activeRun.id !== result.runId ||
    save.activeRun.settled
  )
    return { save, reward: 0, accepted: false };
  const credited = creditRunKills(save, result.runId, result.kills);
  const reward =
    result.won &&
    !result.endless &&
    !credited.completed.includes(result.mission)
      ? 2
      : 0;
  return {
    accepted: true,
    reward,
    save: {
      ...credited,
      activeRun: { ...credited.activeRun!, settled: true },
      completed: reward
        ? [...credited.completed, result.mission].sort((a, b) => a - b)
        : credited.completed,
      points: credited.points + reward,
      best: Math.max(credited.best, result.score),
    },
  };
}
