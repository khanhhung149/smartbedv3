<script lang="ts">
  import { _, json } from 'svelte-i18n';
  import Footer from './Footer.svelte';

  type Section = { heading: string; body: string };
  let { slug, lang }: { slug: 'terms' | 'privacy'; lang: string } = $props();

  let title = $derived(($_ as unknown as (k: string) => string)(`legal.${slug}.title`));
  let intro = $derived(($_ as unknown as (k: string) => string)(`legal.${slug}.intro`));
  let sections = $derived(($json(`legal.${slug}.sections`) as Section[]) ?? []);
  let lastUpdated = $derived(($_ as unknown as (k: string) => string)('legal.last_updated'));
  let backHome = $derived(($_ as unknown as (k: string) => string)('legal.back_to_home'));
</script>

<svelte:head>
  <title>{title} — SleepTech</title>
</svelte:head>

<article class="surface-alt">
  <div class="container-page py-24 lg:py-32 max-w-3xl">
    <a href="/{lang}" class="inline-flex items-center text-sm text-primary dark:text-primary-soft hover:underline mb-8">
      {backHome}
    </a>
    <h1 class="text-4xl md:text-5xl font-bold leading-tight mb-3">{title}</h1>
    <p class="text-sm text-ink/50 dark:text-cloud/50 mb-8">{lastUpdated}</p>
    <p class="text-lg text-ink/80 dark:text-cloud/80 leading-relaxed mb-12">{intro}</p>

    <div class="space-y-10">
      {#each sections as s}
        <section>
          <h2 class="text-xl font-bold mb-3">{s.heading}</h2>
          <p class="text-ink/75 dark:text-cloud/75 leading-relaxed whitespace-pre-line">{s.body}</p>
        </section>
      {/each}
    </div>

    <hr class="my-16 border-ink/10 dark:border-white/10" />
    <p class="text-sm text-ink/60 dark:text-cloud/60">
      © 2026 SleepTech. <a href="mailto:hi@sleeptech.me" class="text-primary dark:text-primary-soft hover:underline">hi@sleeptech.me</a>
    </p>
  </div>
</article>

<Footer />
