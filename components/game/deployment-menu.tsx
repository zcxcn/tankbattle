'use client';
import { useState } from 'react';
import {
  ChevronLeft,
  ChevronRight,
  Check,
  Lock,
  Mountain,
  Building2,
  Play,
  Crosshair,
  Shield,
  Target,
} from 'lucide-react';
import { MISSIONS, CHASSIS, type Save } from '@/lib/campaign';
import {
  BATTLEFIELDS,
  OPERATIONS,
  battlefieldFor,
  type BattlefieldId,
  type OperationId,
} from '@/lib/battlefields';
import { progression } from '@/lib/progression';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import battlefieldCover from '../../web/assets/iron-embers-cover.png?url';

const fieldIcons = {
  city: Building2,
  highlands: Mountain,
};
type Launch = { battlefield: BattlefieldId; operation: OperationId };
export default function DeploymentMenu({
  save,
  ready,
  storageOk,
  selected,
  onSelect,
  onDifficulty,
  onLaunch,
  onGarage,
  onWarmup,
}: {
  save: Save;
  ready: boolean;
  storageOk: boolean;
  selected: number;
  onSelect: (mission: number) => void;
  onDifficulty: (difficulty: number) => void;
  onLaunch: (scenario?: Launch, endless?: boolean) => void;
  onGarage: () => void;
  onWarmup: () => void;
}) {
  const [mode, setMode] = useState('campaign');
  const [setup, setSetup] = useState('field');
  const [actPage, setActPage] = useState({
    selected,
    page: Math.floor(selected / 6),
  });
  const act =
    actPage.selected === selected ? actPage.page : Math.floor(selected / 6);
  const setAct = (update: (page: number) => number) =>
    setActPage({ selected, page: update(act) });
  const [fieldId, setFieldId] = useState<BattlefieldId>('highlands');
  const [operationId, setOperationId] = useState<OperationId>('breakthrough');
  const mission = MISSIONS[selected],
    rank = progression(save.kills);
  const field =
    mode === 'campaign'
      ? battlefieldFor(selected)
      : BATTLEFIELDS.find((f) => f.id === fieldId)!;
  const operation = OPERATIONS.find((o) => o.id === operationId)!;
  const FieldIcon = fieldIcons[field.id];
  return (
    <section className="deployment-menu" aria-label="作战部署">
      <div className="deployment-art" data-biome={field.biome}>
        {/* oxlint-disable-next-line nextjs/no-img-element -- Static Pages uses Vite's hashed asset URLs, without a Next image server. */}
        <img
          src={battlefieldCover}
          alt="主战坦克驶过废墟"
          fetchPriority="high"
          draggable={false}
        />
        <div className="deployment-art-shade" />
        <div className="deployment-wordmark">
          <span>IRON EMBERS</span>
          <h1>钢铁余烬</h1>
          <small>ARMORED OPERATIONS</small>
        </div>
        <div className="deployment-field-stamp">
          <FieldIcon size={24} />
          <div>
            <small>作战区域</small>
            <strong>{field.name}</strong>
            <p>{field.description}</p>
          </div>
        </div>
        <button className="deployment-tank" onClick={onGarage}>
          <Shield size={22} />
          <span>
            <strong>
              {CHASSIS[save.chassis].name} · LV.{rank.level}
            </strong>
            <small>
              {rank.title} / {save.kills} 击毁
            </small>
          </span>
          <ChevronRight size={18} />
        </button>
      </div>
      <div className="deployment-console">
        <Tabs value={mode} onValueChange={setMode}>
          <TabsList className="deployment-modes">
            <TabsTrigger value="campaign">战役</TabsTrigger>
            <TabsTrigger value="skirmish">快速作战</TabsTrigger>
          </TabsList>
        </Tabs>
        <div className="deployment-content">
          {mode === 'campaign' ? (
            <>
              <div className="deployment-mission-title">
                <span>{String(selected + 1).padStart(2, '0')}</span>
                <div>
                  <small>
                    {mission.tag} / {field.name}
                  </small>
                  <h2>{mission.name}</h2>
                </div>
              </div>
              <p className="deployment-brief">{mission.brief}</p>
              <div className="deployment-objective">
                <Target size={18} />
                <span>
                  {mission.objective}
                  <small>本关 Boss：必须击毁</small>
                </span>
              </div>
              <div className="deployment-act">
                <button
                  aria-label="上一幕"
                  disabled={act === 0}
                  onClick={() => setAct((v) => v - 1)}
                >
                  <ChevronLeft size={18} />
                </button>
                <span>
                  {
                    [
                      '第一幕 · 尘湾之夜',
                      '第二幕 · 失联信号',
                      '第三幕 · 回家之路',
                    ][act]
                  }
                </span>
                <button
                  aria-label="下一幕"
                  disabled={act === 2}
                  onClick={() => setAct((v) => v + 1)}
                >
                  <ChevronRight size={18} />
                </button>
              </div>
              <div className="deployment-chapters">
                {MISSIONS.slice(act * 6, act * 6 + 6).map((m, j) => {
                  const i = act * 6 + j,
                    locked = i > 0 && !save.completed.includes(i - 1);
                  return (
                    <button
                      key={i}
                      aria-label={`第 ${i + 1} 章 ${m.name}${locked ? '，需完成前一章' : ''}`}
                      aria-pressed={selected === i}
                      disabled={locked}
                      onClick={() => {
                        onSelect(i);
                        onWarmup();
                      }}
                    >
                      <span>{String(i + 1).padStart(2, '0')}</span>
                      <strong>{m.name}</strong>
                      {save.completed.includes(i) ? (
                        <Check size={14} />
                      ) : locked ? (
                        <Lock size={14} />
                      ) : null}
                    </button>
                  );
                })}
              </div>
            </>
          ) : (
            <>
              <div className="deployment-quick-heading">
                <Crosshair size={22} />
                <div>
                  <h2>{operation.title}</h2>
                  <small>{field.name} · 每局独立部署</small>
                </div>
              </div>
              <Tabs value={setup} onValueChange={setSetup}>
                <TabsList className="deployment-setup-tabs">
                  <TabsTrigger value="field">
                    选择地图 · {BATTLEFIELDS.length}
                  </TabsTrigger>
                  <TabsTrigger value="operation">
                    选择玩法 · {OPERATIONS.length}
                  </TabsTrigger>
                </TabsList>
              </Tabs>
              {setup === 'field' ? (
                <div className="deployment-map-grid">
                  {BATTLEFIELDS.map((f) => {
                    const Icon = fieldIcons[f.id];
                    return (
                      <button
                        key={f.id}
                        data-biome={f.biome}
                        aria-pressed={fieldId === f.id}
                        onClick={() => {
                          setFieldId(f.id);
                          onWarmup();
                        }}
                      >
                        <Icon size={25} />
                        <strong>{f.name}</strong>
                        <small>{f.description}</small>
                        {fieldId === f.id && (
                          <Check className="chosen-tick" size={15} />
                        )}
                      </button>
                    );
                  })}
                </div>
              ) : (
                <div className="deployment-operation-grid">
                  {OPERATIONS.map((o) => (
                    <button
                      key={o.id}
                      aria-pressed={o.id === operationId}
                      onClick={() => {
                        setOperationId(o.id);
                        onWarmup();
                      }}
                    >
                      <strong>{o.title}</strong>
                      <small>{o.description}</small>
                      {o.id === operationId && <Check size={14} />}
                    </button>
                  ))}
                </div>
              )}
              <div className="deployment-objective">
                <Target size={18} />
                <span>
                  {operation.description}
                  <small>同时击毁 Boss · 成长保留 · 战役进度独立</small>
                </span>
              </div>
            </>
          )}
        </div>
        <div className="deployment-actions">
          <fieldset className="deployment-difficulty" aria-label="作战难度">
            {['新兵', '老兵', '王牌'].map((d, i) => (
              <button
                key={d}
                aria-pressed={save.difficulty === i}
                onClick={() => onDifficulty(i)}
              >
                {d}
              </button>
            ))}
          </fieldset>
          <button
            className="deployment-launch"
            disabled={!ready}
            onPointerEnter={onWarmup}
            onFocus={onWarmup}
            onClick={() =>
              onLaunch(
                mode === 'skirmish'
                  ? { battlefield: fieldId, operation: operationId }
                  : undefined,
              )
            }
          >
            <Play size={20} fill="currentColor" />
            <span>{mode === 'campaign' ? '开始行动' : '部署作战'}</span>
            <small>
              {mode === 'campaign'
                ? `CH ${String(selected + 1).padStart(2, '0')}`
                : field.name}
            </small>
          </button>
          <div className="deployment-bottom">
            <span>
              {storageOk
                ? `${save.completed.length} / 18 章节完成`
                : '存档不可用 · 进度暂存'}
            </span>
            <button
              disabled={!ready}
              onPointerEnter={onWarmup}
              onFocus={onWarmup}
              onClick={() =>
                onLaunch({ battlefield: fieldId, operation: operationId }, true)
              }
            >
              无尽生存 <ChevronRight size={14} />
            </button>
          </div>
        </div>
      </div>
    </section>
  );
}
