import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Static SPA built to dist/, uploaded to S3 and served via CloudFront.
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist',
    sourcemap: false,
  },
})
