# Project notes

- Keep the Android version and `pc-godot` outside web-only changes. Run `node scripts/verify-android-baseline.mjs` before delivery.
- After every successful web build, show the local play URL: `http://127.0.0.1:5173/tankbattle/`. Check that the local server is running before describing it as available.
- The published game lives at `https://zcxcn.github.io/tankbattle/`; GitHub Pages contains only static assets, while multiplayer signaling runs separately.
