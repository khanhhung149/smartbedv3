<script lang="ts">
  import '../../app.css';
  import '$lib/i18n';
  import LangSwitcher from '$lib/components/LangSwitcher.svelte';
  import ThemeToggle from '$lib/components/ThemeToggle.svelte';
  import { _ } from 'svelte-i18n';

  let { data, children } = $props();
</script>

<svelte:head>
  <title>{$_('brand')} — {$_('brand_tagline')}</title>
</svelte:head>

<header class="fixed inset-x-0 top-0 z-40 backdrop-blur-md bg-cloud/70 dark:bg-ink/70 border-b border-ink/5 dark:border-white/5">
  <div class="container-page flex h-16 items-center justify-between">
    <a href="/{data.lang}" class="flex items-center" aria-label={$_('brand')}>
      <img
        src="/sleep-tech-logo-ngang.png"
        alt={$_('brand')}
        class="h-8 w-auto dark:invert dark:brightness-200"
        width="180"
        height="56"
      />
    </a>
    <nav class="hidden md:flex items-center gap-8 text-sm font-medium text-ink/70 dark:text-cloud/70">
      <a href="#about" class="hover:text-ink dark:hover:text-cloud transition">{$_('nav.about')}</a>
      <a href="#products" class="hover:text-ink dark:hover:text-cloud transition">{$_('nav.products')}</a>
      <a href="#testimonials" class="hover:text-ink dark:hover:text-cloud transition">{$_('nav.testimonials')}</a>
      <a href="#certifications" class="hover:text-ink dark:hover:text-cloud transition">{$_('nav.certifications')}</a>
      <a href="/{data.lang}/news" class="hover:text-ink dark:hover:text-cloud transition">{$_('nav.news')}</a>
    </nav>
    <div class="flex items-center gap-2">
      <ThemeToggle />
      <LangSwitcher current={data.lang} />
    </div>
  </div>
</header>

<main class="pt-16">
  {@render children?.()}
</main>
