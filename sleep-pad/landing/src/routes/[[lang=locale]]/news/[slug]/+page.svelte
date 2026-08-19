<script lang="ts">
  import { _ } from 'svelte-i18n';
  import { defaultLocale, locales } from '$lib/i18n';
  import { page } from '$app/state';
  import Footer from '$lib/components/Footer.svelte';
  import { listArticles, type ArticleMeta, type ArticleLang } from '$lib/news/articles';
  import type { Component } from 'svelte';

  let { data } = $props();

  let lang = $derived((page.params.lang ?? defaultLocale) as ArticleLang);
  let article: ArticleMeta = $derived(data.article);
  let i18nEntry = $derived(article.i18n[lang] ?? article.i18n['en']);

  // Related articles: same category, excluding current, up to 3
  let related = $derived(
    listArticles()
      .filter((a) => a.slug !== article.slug && a.category === article.category)
      .slice(0, 3)
  );

  // Body component — loaded async when body_module is defined
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let BodyComponent = $state<Component<any> | null>(null);
  let bodyLoading = $state(false);

  $effect(() => {
    // Re-run when lang or article changes
    const loader = article.i18n[lang]?.body_module;
    if (loader) {
      bodyLoading = true;
      BodyComponent = null;
      loader().then((mod) => {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        BodyComponent = (mod as { default: Component<any> }).default;
        bodyLoading = false;
      }).catch(() => {
        bodyLoading = false;
      });
    } else {
      BodyComponent = null;
      bodyLoading = false;
    }
  });

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString(
      lang === 'ja' ? 'ja-JP' : lang === 'th' ? 'th-TH' : lang === 'vi' ? 'vi-VN' : 'en-US',
      { year: 'numeric', month: 'long', day: 'numeric' }
    );
  }

  const ogLocaleMap: Record<ArticleLang, string> = {
    en: 'en_US',
    ja: 'ja_JP',
    th: 'th_TH',
    vi: 'vi_VN',
  };

  let canonicalBase = 'https://sleeptech.me';
  let ogImageUrl = $derived(`${canonicalBase}${article.feature_image}`);
  let ogUrl = $derived(`${canonicalBase}/${lang}/news/${article.slug}`);

  // JSON-LD Article schema
  let jsonLd = $derived(JSON.stringify({
    '@context': 'https://schema.org',
    '@type': 'Article',
    headline: i18nEntry.title,
    description: i18nEntry.excerpt,
    image: ogImageUrl,
    datePublished: article.date,
    inLanguage: ogLocaleMap[lang],
    author: {
      '@type': 'Organization',
      name: 'SleepTech Editorial',
    },
    publisher: {
      '@type': 'Organization',
      name: 'SleepTech',
      url: canonicalBase,
    },
  }));
</script>

<svelte:head>
  <title>{i18nEntry.title} — SleepTech</title>
  <meta name="description" content={i18nEntry.excerpt} />

  <!-- Open Graph -->
  <meta property="og:type" content="article" />
  <meta property="og:title" content="{i18nEntry.title} — SleepTech" />
  <meta property="og:description" content={i18nEntry.excerpt} />
  <meta property="og:image" content={ogImageUrl} />
  <meta property="og:url" content={ogUrl} />
  <meta property="og:locale" content={ogLocaleMap[lang]} />
  <meta property="article:published_time" content={article.date} />

  <!-- Twitter card -->
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="{i18nEntry.title} — SleepTech" />
  <meta name="twitter:description" content={i18nEntry.excerpt} />
  <meta name="twitter:image" content={ogImageUrl} />

  <!-- hreflang for other locales -->
  {#each locales as loc}
    <link rel="alternate" hreflang={loc} href="{canonicalBase}/{loc}/news/{article.slug}" />
  {/each}
  <link rel="alternate" hreflang="x-default" href="{canonicalBase}/en/news/{article.slug}" />

  <!-- JSON-LD -->
  {@html `<script type="application/ld+json">${jsonLd}<\/script>`}
</svelte:head>

<div class="surface-alt min-h-screen">
  <div class="container-page py-12 lg:py-20 max-w-4xl">

    <!-- Back link -->
    <a href="/{lang}/news" class="inline-flex items-center text-sm text-primary dark:text-primary-soft hover:underline mb-8">
      {$_('news.back_to_index')}
    </a>

    <!-- Article header -->
    <header class="mb-8">
      <span class="inline-block text-xs font-semibold uppercase tracking-widest text-primary dark:text-primary-soft mb-3">
        {$_(`news.categories.${article.category}`)}
      </span>
      <h1 class="text-3xl md:text-4xl lg:text-5xl font-bold leading-tight mb-4">
        {i18nEntry.title}
      </h1>
      <div class="flex flex-wrap items-center gap-3 text-sm text-ink/55 dark:text-cloud/55">
        <span>SleepTech Editorial</span>
        <span>·</span>
        <time datetime={article.date}>
          {$_('news.published')} {formatDate(article.date)}
        </time>
        <span>·</span>
        <span>{article.read_minutes} {$_('news.read_time_suffix')}</span>
      </div>
    </header>

    <!-- Hero image -->
    <div class="rounded-3xl overflow-hidden aspect-video mb-10 bg-ink/5 dark:bg-white/5">
      <img
        src={article.feature_image}
        alt={i18nEntry.title}
        class="w-full h-full object-cover"
        width="1200"
        height="675"
      />
    </div>

    <!-- Article body -->
    <div class="prose prose-lg dark:prose-invert max-w-none mb-16">
      {#if bodyLoading}
        <div class="flex items-center gap-3 py-12 text-ink/40 dark:text-cloud/40">
          <span class="animate-spin inline-block w-5 h-5 border-2 border-current border-t-transparent rounded-full"></span>
          <span>Loading…</span>
        </div>
      {:else if BodyComponent}
        <BodyComponent />
      {:else}
        <!-- Coming soon placeholder -->
        <div class="rounded-2xl border border-ink/10 dark:border-white/10 p-8 text-center space-y-4">
          <p class="text-ink/60 dark:text-cloud/60 text-lg">
            Article coming soon — check back shortly. Other languages may be available.
          </p>
          <div class="flex flex-wrap justify-center gap-3">
            {#each locales as loc}
              {#if loc !== lang}
                <a
                  href="/{loc}/news/{article.slug}"
                  class="px-4 py-1.5 rounded-full text-sm font-medium bg-ink/5 dark:bg-white/10 text-ink/70 dark:text-cloud/70 hover:bg-ink/10 dark:hover:bg-white/20 transition"
                >
                  {loc.toUpperCase()}
                </a>
              {/if}
            {/each}
          </div>
        </div>
      {/if}
    </div>

    <!-- Related articles -->
    {#if related.length > 0}
      <section class="border-t border-ink/10 dark:border-white/10 pt-12">
        <h3 class="text-2xl font-bold mb-8">{$_('news.more_articles')}</h3>
        <div class="grid sm:grid-cols-3 gap-6">
          {#each related as rel}
            {@const relEntry = rel.i18n[lang] ?? rel.i18n['en']}
            <a
              href="/{lang}/news/{rel.slug}"
              class="group surface-card rounded-2xl overflow-hidden flex flex-col hover:ring-2 hover:ring-primary/30 transition"
            >
              <div class="aspect-video overflow-hidden bg-ink/5 dark:bg-white/5">
                <img
                  src={rel.feature_image}
                  alt={relEntry.title}
                  class="w-full h-full object-cover group-hover:scale-105 transition duration-500"
                  loading="lazy"
                  width="400"
                  height="225"
                />
              </div>
              <div class="p-4 flex flex-col gap-2 flex-1">
                <span class="text-xs font-semibold uppercase tracking-widest text-primary dark:text-primary-soft">
                  {$_(`news.categories.${rel.category}`)}
                </span>
                <h4 class="text-sm font-bold leading-snug line-clamp-2 text-ink dark:text-cloud group-hover:text-primary dark:group-hover:text-primary-soft transition">
                  {relEntry.title}
                </h4>
                <p class="text-xs text-ink/45 dark:text-cloud/45 mt-auto">
                  {rel.read_minutes} {$_('news.read_time_suffix')}
                </p>
              </div>
            </a>
          {/each}
        </div>
      </section>
    {/if}

  </div>
</div>

<Footer />
