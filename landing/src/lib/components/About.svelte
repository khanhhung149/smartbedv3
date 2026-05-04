<script lang="ts">
  import { _, json } from 'svelte-i18n';

  let pillars = $derived(($json('about.pillars') as Array<{ title: string; body: string }>) ?? []);
</script>

<section id="about" class="section bg-white">
  <div class="container-page">
    <div class="max-w-3xl mb-16">
      <div class="kicker">{$_('about.kicker')}</div>
      <h2 class="text-4xl md:text-5xl font-bold leading-tight mb-6">{$_('about.title')}</h2>
      <p class="text-lg text-ink/70 leading-relaxed">{$_('about.lead')}</p>
    </div>

    <div class="grid md:grid-cols-3 gap-6">
      {#each pillars as p, i}
        <article class="rounded-3xl border border-ink/10 p-8 hover:border-primary/30 hover:shadow-lg transition group">
          <div
            class="w-10 h-10 rounded-xl bg-primary/10 text-primary flex items-center justify-center font-bold mb-5 group-hover:bg-primary group-hover:text-white transition"
          >
            {String(i + 1).padStart(2, '0')}
          </div>
          <h3 class="text-xl font-bold mb-3">{p.title}</h3>
          <p class="text-ink/70 leading-relaxed">{p.body}</p>
        </article>
      {/each}
    </div>
  </div>
</section>
