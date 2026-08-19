import { listArticles } from '$lib/news/articles';
import type { PageLoad } from './$types';

export const prerender = true;

export const load: PageLoad = () => {
  return { articles: listArticles() };
};
