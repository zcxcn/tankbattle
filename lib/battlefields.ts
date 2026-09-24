export const BATTLEFIELDS = [
  {
    id: 'city',
    name: '尘湾城区',
    description: '街区巷战 · 可摧毁楼宇与仓库',
    biome: 'city',
    accent: '#e6b96a',
  },
] as const;
export type BattlefieldId = (typeof BATTLEFIELDS)[number]['id'];
export type Battlefield = {
  readonly id: BattlefieldId;
  readonly name: string;
  readonly description: string;
  readonly biome: string;
  readonly accent: string;
};
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
  shape?: 'ellipse';
  x: number;
  y: number;
  w: number;
  h: number;
  height: number;
};
export function battlefieldFor(
  _mission: number,
  _choice: BattlefieldChoice = 'campaign',
): Battlefield {
  return BATTLEFIELDS[0];
}
