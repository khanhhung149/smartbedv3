<script lang="ts">
  import { _, json } from 'svelte-i18n';

  type Cert = { code: string; label: string };
  let items = $derived(($json('certifications.items') as Cert[]) ?? []);
</script>

<section id="certifications" class="section bg-cloud">
  <div class="container-page">
    <div class="max-w-3xl mb-16">
      <div class="kicker">{$_('certifications.kicker')}</div>
      <h2 class="text-4xl md:text-5xl font-bold leading-tight mb-6">{$_('certifications.title')}</h2>
      <p class="text-lg text-ink/70">{$_('certifications.lead')}</p>
    </div>

    <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
      {#each items as c}
        <div class="rounded-2xl border border-ink/10 bg-white p-5 text-center hover:border-primary/30 transition">
          <div class="font-display font-bold text-lg mb-1">{c.code}</div>
          <div class="text-xs text-ink/60 leading-tight">{c.label}</div>
        </div>
      {/each}
    </div>
  </div>
</section>
