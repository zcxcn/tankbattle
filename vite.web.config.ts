import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/postcss';
import path from 'node:path';

// GitHub Pages lives alongside the owner's existing site at /tankbattle/.
const base = '/tankbattle/';
export default defineConfig({
  root: 'web',
  base,
  publicDir: '../public',
  plugins: [react()],
  define: { __GAME_BASE_PATH__: JSON.stringify(base) },
  resolve: { alias: { '@': path.resolve('.') } },
  css: { postcss: { plugins: [tailwindcss()] } },
  build: {
    outDir: '../outputs/github-pages',
    emptyOutDir: true,
    target: 'chrome100',
    sourcemap: false,
  },
});
