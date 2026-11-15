import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// The Rook marketing site: a static, single-page React build uploaded to S3 by the CDK stack.
export default defineConfig({
  plugins: [react()],
});
