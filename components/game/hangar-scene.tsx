'use client';
import { useEffect, useRef, useState } from 'react';
import type { Hangar } from '@/lib/three/hangar';
export default function HangarScene({
  chassis,
  level = 1,
  disabled = false,
}: {
  chassis: number;
  level?: number;
  disabled?: boolean;
}) {
  const canvas = useRef<HTMLCanvasElement>(null),
    hangar = useRef<Hangar | null>(null),
    latest = useRef({ chassis, level });
  useEffect(() => {
    latest.current = { chassis, level };
  }, [chassis, level]);
  const [ready, setReady] = useState(false);
  useEffect(() => {
    if (disabled) return;
    let disposed = false;
    let resize: ResizeObserver | undefined;
    let intersection: IntersectionObserver | undefined;
    setReady(false);
    void import('@/lib/three/hangar')
      .then(async ({ Hangar }) => {
        if (disposed || !canvas.current) return;
        let h: Hangar;
        try {
          h = new Hangar(
            canvas.current,
            latest.current.chassis,
            latest.current.level,
          );
        } catch {
          return;
        }
        hangar.current = h;
        resize = new ResizeObserver(() => h.resize());
        resize.observe(canvas.current);
        intersection = new IntersectionObserver((entries) =>
          h.setActive(entries[0]?.isIntersecting ?? true),
        );
        intersection.observe(canvas.current);
        h.resize();
        h.start();
        try {
          await h.scene.whenReadyAsync();
          if (!disposed) setReady(true);
        } catch {}
        if (disposed) h.dispose();
      })
      .catch(() => {});
    return () => {
      disposed = true;
      resize?.disconnect();
      intersection?.disconnect();
      hangar.current?.dispose();
      hangar.current = null;
    };
  }, [disabled]);
  useEffect(() => {
    hangar.current?.setChassis(chassis, level);
  }, [chassis, level]);
  return (
    <div
      className={'hangar-surface ' + (ready ? 'ready' : '')}
      aria-hidden="true"
    >
      <canvas ref={canvas} />
      {ready && (
        <span className="live-3d-badge">
          <i />
          LIVE 3D · 实时引擎画面
        </span>
      )}
    </div>
  );
}
