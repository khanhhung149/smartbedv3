import { getArticle } from '$lib/news/articles';
import { error } from '@sveltejs/kit';
import type { PageLoad } from './$types';

export const prerender = true;

export const load: PageLoad = ({ params }) => {
  const slug = params.slug;
  const lang = params.lang ?? 'en';
  const article = getArticle(slug);
  if (!article) {
    error(404, `Article not found: ${slug}`);
  }
  return { slug, lang, article };
};
