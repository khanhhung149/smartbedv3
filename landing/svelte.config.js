import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: vitePreprocess(),
  kit: {
    adapter: adapter({
      pages: 'build',
      assets: 'build',
      fallback: 'index.html',
      precompress: false,
      strict: true
    }),
    prerender: {
      entries: [
        '*',
        '/en', '/ja', '/th', '/vi',
        '/en/terms', '/ja/terms', '/th/terms', '/vi/terms',
        '/en/privacy', '/ja/privacy', '/th/privacy', '/vi/privacy',
        '/en/contact', '/ja/contact', '/th/contact', '/vi/contact'
      ],
      handleMissingId: 'ignore'
    }
  }
};

export default config;
