import { browser } from '$app/environment';
import { init, register, locale as i18nLocale } from 'svelte-i18n';

export const locales = ['en', 'ja', 'th', 'vi'] as const;
export type Locale = (typeof locales)[number];
export const defaultLocale: Locale = 'en';

function initialFromUrl(): Locale {
  if (!browser) return defaultLocale;
  const match = window.location.pathname.match(/^\/(en|ja|th|vi)(?:\/|$)/);
  return (match?.[1] as Locale) ?? defaultLocale;
}

export const localeNames: Record<Locale, string> = {
  en: 'English',
  ja: '日本語',
  th: 'ภาษาไทย',
  vi: 'Tiếng Việt'
};

register('en', () => import('./locales/en.json'));
register('ja', () => import('./locales/ja.json'));
register('th', () => import('./locales/th.json'));
register('vi', () => import('./locales/vi.json'));

// Server (prerender) starts at defaultLocale; +layout.ts then sets params.lang before render.
// Client picks the URL's locale at init time so the very first render matches the server HTML
// (avoids hydration mismatch on prerendered locale-specific pages).
init({
  fallbackLocale: defaultLocale,
  initialLocale: initialFromUrl()
});

export function setLocale(loc: Locale) {
  i18nLocale.set(loc);
}
