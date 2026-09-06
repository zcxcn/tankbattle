'use client';
import { ChevronRight, Shield } from 'lucide-react';
import { progression, MAX_LEVEL } from '@/lib/progression';
export default function CareerProgress({
  kills,
  onOpen,
}: {
  kills: number;
  onOpen?: () => void;
}) {
  const rank = progression(kills);
  return (
    <div
      className="career-progress"
      style={{ '--rank-color': rank.evolution.accent } as React.CSSProperties}
    >
      <div className="career-medal">
        <Shield size={29} />
        <b>{rank.level}</b>
      </div>
      <div className="career-title">
        <small>
          坦克成长 · LV.{String(rank.level).padStart(2, '0')} / {MAX_LEVEL}
        </small>
        <strong>
          {rank.title}
          <span>{rank.evolution.name}</span>
        </strong>
      </div>
      <div className="career-meter">
        <div>
          <span>累计击毁 {rank.kills}</span>
          <b>
            {rank.maxed
              ? '已达最终形态'
              : `再击毁 ${rank.remaining} 辆升至 LV.${rank.level + 1}`}
          </b>
        </div>
        <meter
          min={0}
          max={1}
          value={rank.progress}
          aria-label={`坦克等级 ${rank.level}，${rank.maxed ? '满级' : `距离升级还需击毁 ${rank.remaining} 辆`}`}
        />
      </div>
      {onOpen && (
        <button onClick={onOpen}>
          查看进化
          <ChevronRight size={17} />
        </button>
      )}
    </div>
  );
}
