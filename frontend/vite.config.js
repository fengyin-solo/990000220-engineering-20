import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

const backendPort = process.env.PORT || '3001'
const frontendPort = Number.parseInt(process.env.FRONTEND_PORT || '5173', 10)
const apiProxy = {
  '/api': {
    target: `http://localhost:${backendPort}`,
    changeOrigin: true
  }
}

export default defineConfig({
  plugins: [vue()],
  server: {
    port: frontendPort,
    proxy: apiProxy
  },
  preview: {
    port: frontendPort,
    proxy: apiProxy
  }
})
