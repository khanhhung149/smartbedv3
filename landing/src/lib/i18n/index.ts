import { init, register, locale as i18nLocale } from 'svelte-i18n';

export const locales = ['en', 'ja', 'th', 'vi'] as const;
export type Locale = (typeof locales)[number];
export const defaultLocale: Locale = 'en';

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

// Both server (prerender) and client start at defaultLocale.
// +layout.ts overrides via i18nLocale.set(params.lang) on every nav.
init({
  fallbackLocale: defaultLocale,
  initialLocale: defaultLocale
});

export function setLocale(loc: Locale) {
  i18nLocale.set(loc);
}
