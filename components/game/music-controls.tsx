'use client';
import { useId } from 'react';
import { Music2, Volume2, Minus, Plus } from 'lucide-react';
import { Switch } from '@/components/ui/switch';
import {
  MUSIC_TRACKS,
  type AudioSettings,
  type MusicStatus,
} from '@/lib/music';

export default function MusicControls({
  settings,
  onChange,
  status,
}: {
  settings: AudioSettings;
  onChange: (patch: Partial<AudioSettings>) => void;
  status?: MusicStatus;
}) {
  const id = useId();
  return (
    <div className="music-controls">
      <label className="music-toggle">
        <span>
          <strong>
            <Music2 size={17} />
            背景音乐
          </strong>
          <small>三首战斗配乐 · N / 手柄 View 切换</small>
        </span>
        <Switch
          checked={settings.music}
          onCheckedChange={(music) => onChange({ music })}
          aria-label="背景音乐"
        />
      </label>
      <div
        className="music-track-selector"
        role="group"
        aria-label="战斗配乐选择"
      >
        {MUSIC_TRACKS.map((track, index) => (
          <button
            type="button"
            key={track.file}
            aria-pressed={settings.musicTrack === index}
            onClick={() => onChange({ musicTrack: index })}
          >
            <strong>{track.name}</strong>
            <small>{track.style}</small>
          </button>
        ))}
      </div>
      <div className="music-volume">
        <label htmlFor={id}>
          <Volume2 size={16} />
          音乐音量
        </label>
        <button
          type="button"
          aria-label="降低音乐音量"
          disabled={settings.musicVolume <= 0}
          onClick={() =>
            onChange({ musicVolume: Math.max(0, settings.musicVolume - 10) })
          }
        >
          <Minus size={15} />
        </button>
        <input
          id={id}
          type="range"
          min="0"
          max="100"
          step="5"
          value={settings.musicVolume}
          aria-label="音乐音量"
          onChange={(event) =>
            onChange({ musicVolume: Number(event.target.value) })
          }
        />
        <button
          type="button"
          aria-label="提高音乐音量"
          disabled={settings.musicVolume >= 100}
          onClick={() =>
            onChange({ musicVolume: Math.min(100, settings.musicVolume + 10) })
          }
        >
          <Plus size={15} />
        </button>
        <output htmlFor={id}>{settings.musicVolume}%</output>
      </div>
      {status === 'locked' && settings.music && (
        <small className="music-hint">点击页面或按任意键开始播放音乐</small>
      )}
      {status === 'loading' && (
        <small className="music-hint">正在准备配乐…</small>
      )}
      {status === 'error' && (
        <small className="music-hint">
          音乐暂时未能加载，点击音乐开关可重试
        </small>
      )}
    </div>
  );
}
