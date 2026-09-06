import { createRoot } from 'react-dom/client';
import Home from './baseline/app/page';
import './baseline/app/globals.css';
import { deviceState, type DeviceState } from './baseline/lib/performance';

// Long holds are game input; native text-selection menus must not cover controls.
window.addEventListener('contextmenu', (event) => {
  if (
    event.target instanceof Element &&
    event.target.closest('input, textarea, [contenteditable="true"]')
  )
    return;
  event.preventDefault();
});

let recovery = 0;
// Native sends plain state events; it never exposes filesystem or general Java APIs.
window.addEventListener('tank-native-update', (event) => {
  const state = (event as CustomEvent<DeviceState>).detail;
  if (!state || !Number.isInteger(state.thermal)) return;
  const thermal = Math.max(0, Math.min(6, state.thermal));
  deviceState.background = state.background === true;
  deviceState.powerSave = state.powerSave === true;
  window.clearTimeout(recovery);
  if (thermal >= deviceState.thermal) deviceState.thermal = thermal;
  else
    recovery = window.setTimeout(() => {
      deviceState.thermal = thermal;
      window.dispatchEvent(new Event('tank-native-state'));
    }, 45000);
  window.dispatchEvent(new Event('tank-native-state'));
});

createRoot(document.getElementById('root')!).render(
  <>
    <Home />
    <aside className="rotate-phone">
      <b>请横屏进入战场</b>
      <p>
        转动手机，双手握持。左手移动，右手瞄准与开火，也支持连接手柄和鼠标。
      </p>
    </aside>
  </>,
);
