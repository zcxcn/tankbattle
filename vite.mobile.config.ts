import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/postcss';
import path from 'node:path';

export default defineConfig({
  root: 'mobile',
  publicDir: '../public',
  plugins: [
    {
      name: 'offline-mobile-textures',
      enforce: 'pre',
      transform(source, id) {
        if (!/\.(tsx?|css)$/.test(id) || id.includes('node_modules')) return;
        return source
          .replaceAll('/armor-texture.png', '/mobile/armor.webp')
          .replaceAll('/ground-texture.png', '/mobile/ground.webp')
          .replaceAll('/keyart.png', '/mobile/keyart.webp');
      },
      generateBundle(_options, bundle) {
        const projectRoot = path.resolve('.').replaceAll('\\', '/') + '/';
        for (const item of Object.values(bundle)) {
          if (item.type !== 'chunk') continue;
          for (const id of Object.keys(item.modules)) {
            const relative = id.replaceAll('\\', '/').replace(projectRoot, '');
            if (/^(app\/|lib\/|components\/game\/)/.test(relative))
              this.error(
                'Android must use its frozen baseline, not upgraded web code: ' +
                  relative,
              );
          }
        }
      },
    },
    react(),
  ],
  // Android keeps the exact pre-upgrade game; web work cannot enter its bundle.
  resolve: {
    alias: {
      '@/lib': path.resolve('mobile/baseline/lib'),
      '@/components/game': path.resolve('mobile/baseline/components/game'),
      '@': path.resolve('.'),
    },
  },
  css: { postcss: { plugins: [tailwindcss()] } },
  build: {
    outDir: '../outputs/android-web',
    emptyOutDir: true,
    target: 'chrome100',
    sourcemap: false,
  },
});
