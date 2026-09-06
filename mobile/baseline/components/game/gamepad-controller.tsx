'use client';
import { useEffect, useRef, useState } from 'react';
import { Gamepad2 } from 'lucide-react';
import { PadReader, type PadFrame } from '@/lib/gamepad';

function navigateMenu(frame: PadFrame, onBack: () => void) {
  const dialog = Array.from(
    document.querySelectorAll<HTMLElement>(
      '[data-slot="dialog-content"][data-open]',
    ),
  ).at(-1);
  const root =
    dialog ??
    document.querySelector<HTMLElement>('[data-gamepad-menu="error"]') ??
    document.querySelector<HTMLElement>('.command-app');
  if (!root) return;
  const candidates = Array.from(
    root.querySelectorAll<HTMLElement>('button, [role="switch"], [role="tab"]'),
  ).filter(
    (el) =>
      !el.closest('[inert], [aria-hidden="true"]') &&
      !el.hasAttribute('disabled') &&
      el.getAttribute('aria-disabled') !== 'true' &&
      el.getClientRects().length > 0 &&
      getComputedStyle(el).visibility !== 'hidden',
  );
  if (!candidates.length) return;
  let focus = document.activeElement as HTMLElement;
  if (!candidates.includes(focus))
    focus =
      candidates.find((el) => el.classList.contains('deploy-button')) ??
      candidates[0];
  else if (frame.direction) {
    const r = focus.getBoundingClientRect(),
      cx = r.x + r.width / 2,
      cy = r.y + r.height / 2;
    const options = candidates
      .filter((el) => el !== focus)
      .map((el) => {
        const q = el.getBoundingClientRect(),
          dx = q.x + q.width / 2 - cx,
          dy = q.y + q.height / 2 - cy;
        const forward =
          frame.direction === 1
            ? -dy
            : frame.direction === 2
              ? dx
              : frame.direction === 3
                ? dy
                : -dx;
        const side =
          frame.direction === 1 || frame.direction === 3
            ? Math.abs(dx)
            : Math.abs(dy);
        return { el, forward, score: Math.hypot(dx, dy) + side * 1.8 };
      })
      .filter((v) => v.forward > 8)
      .sort((a, b) => a.score - b.score);
    if (options[0]) focus = options[0].el;
  }
  if (frame.direction || frame.confirm) {
    document
      .querySelectorAll('.gamepad-focused')
      .forEach((el) => el.classList.remove('gamepad-focused'));
    focus.classList.add('gamepad-focused');
    focus.focus({ preventScroll: true });
    focus.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }
  if (frame.back) {
    onBack();
    return;
  }
  if (frame.confirm) focus.click();
}
export default function GamepadController({
  inBattle,
  onBack,
  onNextMusic,
}: {
  inBattle: boolean;
  onBack: () => void;
  onNextMusic: () => void;
}) {
  const latest = useRef({ inBattle, onBack, onNextMusic });
  useEffect(() => {
    latest.current = { inBattle, onBack, onNextMusic };
  }, [inBattle, onBack, onNextMusic]);
  const [connected, setConnected] = useState(false);
  useEffect(() => {
    const reader = new PadReader();
    let raf = 0,
      wasConnected = false,
      nextPoll = 0;
    const loop = (now: number) => {
      raf = requestAnimationFrame(loop);
      if (document.hidden || now < nextPoll) return;
      nextPoll = now + (wasConnected ? 16 : 250);
      let pads: (Gamepad | null)[] = [];
      try {
        pads = Array.from(navigator.getGamepads?.() ?? []);
      } catch {}
      const frame = reader.sample(pads, now);
      if (frame.connected !== wasConnected) {
        wasConnected = frame.connected;
        setConnected(frame.connected);
      }
      if (!document.hidden && document.hasFocus()) {
        if (frame.music) latest.current.onNextMusic();
        if (latest.current.inBattle)
          window.dispatchEvent(
            new CustomEvent<PadFrame>('tank-gamepad', { detail: frame }),
          );
        if (frame.direction || frame.confirm || frame.back) {
          const pauseDialog = document.querySelector(
            '[data-slot="dialog-content"][data-open].pause-dialog',
          );
          const errorMenu = document.querySelector<HTMLElement>(
            '[data-gamepad-menu="error"]',
          );
          if (
            (!latest.current.inBattle || pauseDialog || errorMenu) &&
            (frame.direction || frame.confirm || frame.back)
          ) {
            navigateMenu(frame, () => {
              if (errorMenu)
                errorMenu.querySelector<HTMLButtonElement>('button')?.click();
              else if (pauseDialog)
                window.dispatchEvent(new CustomEvent('tank-gamepad-resume'));
              else latest.current.onBack();
            });
          }
        }
      }
    };
    raf = requestAnimationFrame(loop);
    const musicKey = (event: KeyboardEvent) => {
      if (
        !event.repeat &&
        !event.ctrlKey &&
        !event.metaKey &&
        !event.altKey &&
        event.key.toLowerCase() === 'n' &&
        !(
          event.target instanceof HTMLElement &&
          event.target.matches('input,textarea,select,[contenteditable="true"]')
        )
      )
        latest.current.onNextMusic();
    };
    window.addEventListener('keydown', musicKey);
    const connectedEvent = () => {
      nextPoll = 0;
    };
    window.addEventListener('gamepadconnected', connectedEvent);
    window.addEventListener('gamepaddisconnected', connectedEvent);
    const mouse = () =>
      document
        .querySelectorAll('.gamepad-focused')
        .forEach((el) => el.classList.remove('gamepad-focused'));
    window.addEventListener('pointerdown', mouse);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('keydown', musicKey);
      window.removeEventListener('pointerdown', mouse);
      window.removeEventListener('gamepadconnected', connectedEvent);
      window.removeEventListener('gamepaddisconnected', connectedEvent);
      mouse();
    };
  }, []);
  return (
    <output className="gamepad-status">
      <Gamepad2 size={16} />
      {connected ? '手柄已连接 · A 确认 / B 返回' : '支持手柄 · 连接后按任意键'}
    </output>
  );
}
