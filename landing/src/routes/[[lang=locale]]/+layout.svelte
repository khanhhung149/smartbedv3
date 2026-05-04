<script lang="ts">
  import '../../app.css';
  import '$lib/i18n';
  import LangSwitcher from '$lib/components/LangSwitcher.svelte';
  import { _ } from 'svelte-i18n';

  let { data, children } = $props();
</script>

<svelte:head>
  <title>{$_('brand')} — {$_('brand_tagline')}</title>
</svelte:head>

<header class="fixed inset-x-0 top-0 z-40 backdrop-blur-md bg-cloud/70 border-b border-ink/5">
  <div class="container-page flex h-16 items-center justify-between">
    <a href="/{data.lang}" class="flex items-center gap-2 font-display font-bold text-lg tracking-tight">
      <span class="inline-block w-2 h-2 rounded-full bg-primary"></span>
      {$_('brand')}
    </a>
    <nav class="hidden md:flex items-center gap-8 text-sm font-medium text-ink/70">
      <a href="#about" class="hover:text-ink transition">{$_('nav.about')}</a>
      <a href="#products" class="hover:text-ink transition">{$_('nav.products')}</a>
      <a href="#testimonials" class="hover:text-ink transition">{$_('nav.testimonials')}</a>
      <a href="#certifications" class="hover:text-ink transition">{$_('nav.certifications')}</a>
    </nav>
    <LangSwitcher current={data.lang} />
  </div>
</header>

<main class="pt-16">
  {@render children?.()}
</main>
