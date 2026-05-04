<script lang="ts">
  import { _ } from 'svelte-i18n';
</script>

<section id="cta" class="section bg-ink text-white relative overflow-hidden">
  <div class="absolute inset-0 -z-10">
    <div class="absolute -top-40 left-1/4 w-[600px] h-[600px] rounded-full bg-primary/20 blur-3xl"></div>
    <div class="absolute -bottom-40 right-1/4 w-[600px] h-[600px] rounded-full bg-sakura/10 blur-3xl"></div>
  </div>
  <div class="container-page text-center max-w-3xl">
    <div class="kicker !text-sakura">{$_('cta.kicker')}</div>
    <h2 class="text-4xl md:text-6xl font-bold leading-tight mb-6">{$_('cta.title')}</h2>
    <p class="text-lg text-white/70 mb-10">{$_('cta.lead')}</p>
    <div class="flex flex-wrap gap-3 justify-center">
      <a href="mailto:hi@sleeptech.me" class="inline-flex items-center justify-center rounded-full bg-white text-ink px-8 py-4 text-sm font-semibold hover:bg-cloud transition">
        {$_('cta.primary')}
      </a>
      <a href="mailto:hi@sleeptech.me" class="inline-flex items-center justify-center rounded-full border border-white/30 px-8 py-4 text-sm font-semibold hover:bg-white/10 transition">
        {$_('cta.secondary')}
      </a>
    </div>
  </div>
</section>
