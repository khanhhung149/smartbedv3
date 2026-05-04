<script lang="ts">
  import { _, json } from 'svelte-i18n';

  type Item = { quote: string; author: string; location: string; verified: string };
  let items = $derived(($json('testimonials.items') as Item[]) ?? []);
</script>

<section id="testimonials" class="section bg-white">
  <div class="container-page">
    <div class="max-w-3xl mb-16">
      <div class="kicker">{$_('testimonials.kicker')}</div>
      <h2 class="text-4xl md:text-5xl font-bold leading-tight mb-6">{$_('testimonials.title')}</h2>
      <p class="text-lg text-ink/70">{$_('testimonials.lead')}</p>
    </div>

    <div class="grid md:grid-cols-2 gap-6">
      {#each items as t}
        <figure class="rounded-3xl border border-ink/10 bg-cloud/40 p-8">
          <svg class="w-8 h-8 text-primary/50 mb-4" viewBox="0 0 32 32" fill="currentColor">
            <path d="M9.4 7.5C5.5 9.6 3 13.4 3 18v6h7v-7H6c0-3.5 2-6.6 5.5-7.7l-2.1-1.8zM21 7.5c-3.9 2.1-6.4 5.9-6.4 10.5v6h7v-7h-4c0-3.5 2-6.6 5.5-7.7L21 7.5z" />
          </svg>
          <blockquote class="text-lg leading-relaxed text-ink/85 mb-6">"{t.quote}"</blockquote>
          <figcaption class="flex items-center gap-3">
            <div
              class="w-10 h-10 rounded-full bg-gradient-to-br from-primary to-sakura flex items-center justify-center text-white font-bold text-sm"
            >
              {t.author.charAt(0)}
            </div>
            <div>
              <div class="font-semibold text-sm">{t.author}</div>
              <div class="text-xs text-ink/50">{t.location} · {t.verified}</div>
            </div>
          </figcaption>
        </figure>
      {/each}
    </div>
  </div>
</section>
