import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  root: 'nui',
  base: './',
  publicDir: 'public',
  plugins: [react()],
  build: {
    outDir: '../ui',
    emptyOutDir: true,
    target: 'es2020',
    cssCodeSplit: false,
    sourcemap: false,
    rollupOptions: {
      output: {
        entryFileNames: 'app.js',
        chunkFileNames: 'app.js',
        assetFileNames: (assetInfo) => {
          if (assetInfo.name && assetInfo.name.endsWith('.css')) {
            return 'style.css';
          }
          return 'assets/[name][extname]';
        }
      }
    }
  },
  server: {
    host: '127.0.0.1',
    port: 5173
  }
});
