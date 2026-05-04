import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

const LANGS = ['en', 'ja', 'th', 'vi'];

const NEWS_SLUGS = [
  'how-ai-revolutionizes-sleep-monitoring',
  'heart-rate-variability-explained',
  'wearables-vs-non-contact-sensors',
  'privacy-first-sleep-ai',
  'ballistocardiography-future-sleep-tech',
  'realtime-vital-alerts-balance',
  'sleep-apnea-detection-at-home',
  'sustainable-sleep-routine-with-data',
  'hrv-and-sleep-quality',
  'bedroom-climate-and-sleep-stages',
  'snoring-detection-with-ai',
  'mindful-pre-sleep-routines-with-data',
  'tracking-elderly-sleep-patterns',
  'shift-workers-sleep-strategies',
  'caring-from-afar-night-monitoring',
  'bed-presence-detection-fall-prevention',
  'caring-elders-japan-tradition-meets-ai',
  'yumepad-first-night-setup-elderly-parent',
  'real-family-stories-peace-of-mind',
  'nighttime-caregiver-burden-tech-relief',
];

// 4 langs × (1 index + 20 articles) = 84 news entries
const newsEntries = LANGS.flatMap((lang) => [
  `/${lang}/news`,
  ...NEWS_SLUGS.map((slug) => `/${lang}/news/${slug}`),
]);

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
        '/en/contact', '/ja/contact', '/th/contact', '/vi/contact',
        ...newsEntries,
      ],
      handleMissingId: 'ignore'
    }
  }
};

export default config;
