import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  esbuild: {
    legalComments: 'none'
  },
  base: './',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
});
