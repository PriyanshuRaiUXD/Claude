import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

const API_TARGET = `http://localhost:${process.env.PORT || 3001}`;

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist/client',
    emptyOutDir: true,
    sourcemap: false,
    // hls.js (~520 kB) is its own lazily-loaded chunk, only fetched for .m3u8 links.
    chunkSizeWarningLimit: 600,
  },
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      '/api': { target: API_TARGET, changeOrigin: false },
      '/socket.io': { target: API_TARGET, ws: true, changeOrigin: false },
    },
  },
});
