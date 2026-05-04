<script lang="ts">
  import { _ } from 'svelte-i18n';
  import { defaultLocale } from '$lib/i18n';
  import { page } from '$app/state';
  import Footer from '$lib/components/Footer.svelte';
  import type { ArticleCategory, ArticleMeta } from '$lib/news/articles';

  let { data } = $props();

  let lang = $derived((page.params.lang ?? defaultLocale) as string);
  let activeCategory = $state<ArticleCategory | 'all'>('all');

  let categories: { id: ArticleCategory | 'all'; label: string }[] = $derived([
    { id: 'all', label: ($_)('lang.switch') === 'Language' ? 'All' : 'すべて' },
    { id: 'sleep_tech_ai', label: ($_)('news.categories.sleep_tech_ai') },
    { id: 'sleep_care', label: ($_)('news.categories.sleep_care') },
    { id: 'elderly_care', label: ($_)('news.categories.elderly_care') },
  ]);

  // Simple localized "All" label by checking locale
  let allLabel = $derived(
    lang === 'ja' ? 'すべて'
    : lang === 'th' ? 'ทั้งหมด'
    : lang === 'vi' ? 'Tất cả'
    : 'All'
  );

  let filteredArticles: ArticleMeta[] = $derived(
    activeCategory === 'all'
      ? data.articles
      : data.articles.filter((a: ArticleMeta) => a.category === activeCategory)
  );

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString(
      lang === 'ja' ? 'ja-JP' : lang === 'th' ? 'th-TH' : lang === 'vi' ? 'vi-VN' : 'en-US',
      { year: 'numeric', month: 'long', day: 'numeric' }
    );
  }
</script>

<svelte:head>
  <title>{$_('news.title')} — SleepTech</title>
  <meta name="description" content={$_('news.lead')} />
  <meta property="og:title" content="{$_('news.title')} — SleepTech" />
  <meta property="og:description" content={$_('news.lead')} />
  <meta property="og:type" content="website" />
</svelte:head>

<article class="surface-alt min-h-screen">
  <!-- Hero header -->
  <div class="container-page py-20 lg:py-28">
    <a href="/{lang}" class="inline-flex items-center text-sm text-primary dark:text-primary-soft hover:underline mb-8">
      {$_('news.back_to_home')}
    </a>
    <p class="text-xs font-semibold uppercase tracking-widest text-primary dark:text-primary-soft mb-3">
      {$_('news.kicker')}
    </p>
    <h1 class="text-4xl md:text-5xl lg:text-6xl font-bold leading-tight mb-6 max-w-3xl">
      {$_('news.title')}
    </h1>
    <p class="text-lg text-ink/70 dark:text-cloud/70 leading-relaxed max-w-2xl">
      {$_('news.lead')}
    </p>
  </div>

  <!-- Category filter -->
  <div class="border-t border-ink/10 dark:border-white/10">
    <div class="container-page py-4 flex flex-wrap gap-2">
      <button
        onclick={() => { activeCategory = 'all'; }}
        class="px-4 py-1.5 rounded-full text-sm font-medium transition
          {activeCategory === 'all'
            ? 'bg-primary text-white dark:bg-primary-soft dark:text-ink'
            : 'bg-ink/5 dark:bg-white/10 text-ink/70 dark:text-cloud/70 hover:bg-ink/10 dark:hover:bg-white/20'}"
      >
        {allLabel}
      </button>
      {#each categories.filter(c => c.id !== 'all') as cat}
        <button
          onclick={() => { activeCategory = cat.id as ArticleCategory; }}
          class="px-4 py-1.5 rounded-full text-sm font-medium transition
            {activeCategory === cat.id
              ? 'bg-primary text-white dark:bg-primary-soft dark:text-ink'
              : 'bg-ink/5 dark:bg-white/10 text-ink/70 dark:text-cloud/70 hover:bg-ink/10 dark:hover:bg-white/20'}"
        >
          {cat.label}
        </button>
      {/each}
    </div>
  </div>

  <!-- Article grid -->
  <div class="container-page py-12 pb-24">
    {#if filteredArticles.length === 0}
      <p class="text-ink/50 dark:text-cloud/50 text-center py-20">No articles found.</p>
    {:else}
      <div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-8">
        {#each filteredArticles as article}
          {@const i18nEntry = article.i18n[lang as 'en' | 'ja' | 'th' | 'vi'] ?? article.i18n['en']}
          <a
            href="/{lang}/news/{article.slug}"
            class="group surface-card rounded-2xl overflow-hidden flex flex-col hover:ring-2 hover:ring-primary/30 transition"
          >
            <!-- Feature image -->
            <div class="aspect-video overflow-hidden bg-ink/5 dark:bg-white/5">
              <img
                src={article.feature_image}
                alt={i18nEntry.title}
                class="w-full h-full object-cover group-hover:scale-105 transition duration-500"
                loading="lazy"
                width="800"
                height="450"
              />
            </div>

            <!-- Card body -->
            <div class="flex flex-col flex-1 p-5 gap-3">
              <!-- Category badge -->
              <span class="inline-block text-xs font-semibold uppercase tracking-widest text-primary dark:text-primary-soft w-fit">
                {$_(`news.categories.${article.category}`)}
              </span>

              <h3 class="text-lg font-bold leading-snug text-ink dark:text-cloud group-hover:text-primary dark:group-hover:text-primary-soft transition line-clamp-2">
                {i18nEntry.title}
              </h3>

              <p class="text-sm text-ink/65 dark:text-cloud/65 leading-relaxed line-clamp-3 flex-1">
                {i18nEntry.excerpt}
              </p>

              <!-- Date + read time -->
              <div class="flex items-center gap-2 text-xs text-ink/45 dark:text-cloud/45 mt-auto pt-2 border-t border-ink/8 dark:border-white/8">
                <time datetime={article.date}>{formatDate(article.date)}</time>
                <span>·</span>
                <span>{article.read_minutes} {$_('news.read_time_suffix')}</span>
              </div>
            </div>
          </a>
        {/each}
      </div>
    {/if}
  </div>
</article>

<Footer />
