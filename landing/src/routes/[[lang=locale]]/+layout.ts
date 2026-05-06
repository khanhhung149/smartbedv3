import { defaultLocale, type Locale } from '$lib/i18n';
import { waitLocale, locale as i18nLocale } from 'svelte-i18n';
import type { LayoutLoad } from './$types';

export const prerender = true;

export const load: LayoutLoad = async ({ params }) => {
  const lang = (params.lang ?? defaultLocale) as Locale;
  i18nLocale.set(lang);
  await waitLocale(lang);
  return { lang };
};
