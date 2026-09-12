export const BATTLEFIELDS = [
  {
    id: 'city',
    name: '尘湾城区',
    description: '街区巷战 · 可摧毁楼宇与仓库',
    biome: 'city',
    accent: '#e6b96a',
  },
  {
    id: 'highlands',
    name: '苍岩高地',
    description: '山谷迂回 · 岩丘与林间道路',
    biome: 'highlands',
    accent: '#9ebc9a',
  },
  {
    id: 'desert',
    name: '赤沙荒漠',
    description: '开阔机动 · 台地与补给哨站',
    biome: 'desert',
    accent: '#e9af70',
  },
  {
    id: 'tropical',
    name: '雨林河谷',
    description: '丛林穿插 · 河道与桥梁',
    biome: 'tropical',
    accent: '#72c7a0',
  },
  {
    id: 'railway',
    name: '断轨货场',
    description: '铁路争夺 · 货列与装卸区',
    biome: 'railway',
    accent: '#b5b7cb',
  },
  {
    id: 'wetlands',
    name: '雾湾湿地',
    description: '桥头突破 · 河网与堤岸',
    biome: 'wetlands',
    accent: '#80bfd1',
  },
] as const;
export type Battlefield = (typeof BATTLEFIELDS)[number];
export type BattlefieldId = Battlefield['id'];
export type BattlefieldChoice = 'campaign' | BattlefieldId;
export const OPERATIONS = [
  {
    id: 'assault',
    title: '歼灭突击',
    description: '清除指定敌军并击毁指挥战车。',
  },
  {
    id: 'defend',
    title: '信标防守',
    description: '保护南侧信标，守住阵地直到倒计时结束。',
  },
  {
    id: 'capture',
    title: '区域控制',
    description: '夺取三座中继站，敌军靠近时停止占领。',
  },
  {
    id: 'escort',
    title: '车队护送',
    description: '靠近运输车引导前进，清除沿途威胁。',
  },
  {
    id: 'extract',
    title: '情报撤离',
    description: '深入敌阵收集三份情报，再返回撤离区。',
  },
  {
    id: 'sabotage',
    title: '设施破袭',
    description: '炮击摧毁三座储能设施，切断敌军补给。',
  },
  {
    id: 'breakthrough',
    title: '纵深突破',
    description: '依次抵达三个前进路标，最后突破北侧封锁。',
  },
  {
    id: 'survival',
    title: '限时生存',
    description: '独立作战，抵抗持续增援直到救援窗口开启。',
  },
] as const;
export type OperationId = (typeof OPERATIONS)[number]['id'];
export type OperationChoice = 'campaign' | OperationId;
export type TerrainFeature = {
  kind: 'water' | 'hill' | 'bridge' | 'rail';
  x: number;
  y: number;
  w: number;
  h: number;
  height: number;
};
const CAMPAIGN_FIELDS: BattlefieldId[] = [
  'city',
  'wetlands',
  'railway',
  'city',
  'desert',
  'city',
  'highlands',
  'tropical',
  'desert',
  'railway',
  'wetlands',
  'highlands',
  'tropical',
  'wetlands',
  'railway',
  'desert',
  'highlands',
  'city',
];
export function battlefieldFor(
  mission: number,
  choice: BattlefieldChoice = 'campaign',
): Battlefield {
  const id =
    choice === 'campaign' ? (CAMPAIGN_FIELDS[mission] ?? 'city') : choice;
  return BATTLEFIELDS.find((field) => field.id === id) ?? BATTLEFIELDS[0];
}
