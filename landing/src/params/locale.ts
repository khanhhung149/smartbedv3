import { locales } from '$lib/i18n';
import type { ParamMatcher } from '@sveltejs/kit';

export const match: ParamMatcher = (param) => locales.includes(param as (typeof locales)[number]);
