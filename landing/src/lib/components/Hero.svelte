<script lang="ts">
  import { _ } from 'svelte-i18n';
</script>

<section class="relative overflow-hidden min-h-[90vh] flex items-center">
  <!-- Generated hero (Veo 3 video loop with Imagen poster fallback) -->
  <div class="absolute inset-0 -z-10">
    <video
      src="/generated/hero-loop.mp4"
      poster="/generated/hero-bedroom-jp.png"
      class="absolute inset-0 w-full h-full object-cover"
      autoplay
      muted
      loop
      playsinline
    ></video>
    <div class="absolute inset-0 bg-gradient-to-br from-cloud/95 via-cloud/70 to-cloud/55"></div>
    <div class="absolute inset-0 bg-gradient-to-t from-cloud via-transparent to-transparent"></div>
  </div>

  <div class="container-page py-32 lg:py-44">
    <div class="max-w-3xl">
      <div class="kicker">
        <span class="inline-block w-1 h-1 rounded-full bg-primary"></span>
        {$_('hero.kicker')}
      </div>
      <h1 class="text-5xl md:text-7xl font-bold leading-[1.05] mb-8">
        <span class="block">{$_('hero.title_1')}</span>
        <span
          class="block bg-gradient-to-r from-primary via-accent to-sakura bg-clip-text text-transparent"
        >
          {$_('hero.title_2')}
        </span>
      </h1>
      <p class="text-lg md:text-xl text-ink/70 leading-relaxed mb-10 max-w-2xl">
        {$_('hero.subtitle')}
      </p>
      <div class="flex flex-wrap gap-3">
        <a href="#products" class="btn-primary">{$_('hero.cta_primary')}</a>
        <a href="#about" class="btn-ghost">{$_('hero.cta_secondary')}</a>
      </div>
    </div>
  </div>

  <div class="absolute bottom-8 left-1/2 -translate-x-1/2 text-xs uppercase tracking-widest text-ink/40">
    {$_('hero.scroll_hint')}
  </div>
</section>
