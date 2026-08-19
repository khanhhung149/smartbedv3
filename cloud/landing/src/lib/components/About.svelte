<script lang="ts">
  import { _, json } from 'svelte-i18n';

  let pillars = $derived(($json('about.pillars') as Array<{ title: string; body: string }>) ?? []);
  let stats = $derived(
    ($json('about.stats') as Array<{ value: string; label: string }>) ?? []
  );
  let awards = $derived(
    ($json('about.awards') as Array<{ year: string; name: string }>) ?? []
  );
</script>

<section id="about" class="section surface">
  <div class="container-page">

    <!-- Section header -->
    <div class="max-w-3xl mb-16">
      <div class="kicker">{$_('about.kicker')}</div>
      <h2 class="text-4xl md:text-5xl font-bold leading-tight mb-6">{$_('about.title')}</h2>
      <p class="text-lg text-ink/70 dark:text-cloud/70 leading-relaxed">{$_('about.lead')}</p>
    </div>

    <!-- Heritage hero: photo + story + stats -->
    <div class="grid lg:grid-cols-2 gap-10 lg:gap-16 items-center mb-20">
      <!-- Photo -->
      <div class="order-2 lg:order-1">
        <img
          src="/generated/about-heritage.png"
          alt="Multi-generational Japanese family scene"
          class="w-full rounded-3xl object-cover aspect-[4/5] lg:aspect-auto lg:h-[500px]"
          loading="lazy"
        />
      </div>

      <!-- Story + stats -->
      <div class="order-1 lg:order-2 flex flex-col gap-8">
        <p class="text-base md:text-lg text-ink/80 dark:text-cloud/80 leading-relaxed">
          {$_('about.story')}
        </p>

        <!-- Stats row -->
        <div class="grid grid-cols-3 gap-4 pt-4 border-t border-ink/10 dark:border-white/10">
          {#each stats as stat}
            <div class="flex flex-col gap-1">
              <span class="text-3xl md:text-4xl font-bold text-primary dark:text-primary-soft">
                {stat.value}
              </span>
              <span class="text-xs text-ink/60 dark:text-cloud/60 leading-snug">{stat.label}</span>
            </div>
          {/each}
        </div>
      </div>
    </div>

    <!-- Pillars grid -->
    <div class="grid md:grid-cols-3 gap-6 mb-20">
      {#each pillars as p, i}
        <article
          class="rounded-3xl border border-ink/10 dark:border-white/10 p-8 hover:border-primary/30 dark:hover:border-primary-soft/40 hover:shadow-lg transition group"
        >
          <div
            class="w-10 h-10 rounded-xl bg-primary/10 text-primary dark:bg-primary-soft/10 dark:text-primary-soft flex items-center justify-center font-bold mb-5 group-hover:bg-primary group-hover:text-white transition"
          >
            {String(i + 1).padStart(2, '0')}
          </div>
          <h3 class="text-xl font-bold mb-3">{p.title}</h3>
          <p class="text-ink/70 dark:text-cloud/70 leading-relaxed">{p.body}</p>
        </article>
      {/each}
    </div>

    <!-- Global reach band -->
    <div
      class="rounded-3xl overflow-hidden border border-ink/10 dark:border-white/10 grid md:grid-cols-2 mb-20"
    >
      <div class="relative min-h-[260px]">
        <img
          src="/generated/about-global.png"
          alt="World map showing SleepTech's global reach"
          class="absolute inset-0 w-full h-full object-cover"
          loading="lazy"
        />
      </div>
      <div class="p-10 flex flex-col justify-center surface-card">
        <h3 class="text-2xl md:text-3xl font-bold mb-4">{$_('about.regions_title')}</h3>
        <p class="text-ink/70 dark:text-cloud/70 leading-relaxed">{$_('about.regions_lead')}</p>
      </div>
    </div>

    <!-- Awards section -->
    <div class="grid lg:grid-cols-3 gap-10 items-start">
      <!-- Awards list — 2/3 -->
      <div class="lg:col-span-2">
        <h3 class="text-2xl md:text-3xl font-bold mb-2">{$_('about.awards_title')}</h3>
        <p class="text-ink/60 dark:text-cloud/60 mb-8 leading-relaxed">
          {$_('about.awards_lead')}
        </p>
        <div class="flex flex-col divide-y divide-ink/10 dark:divide-white/10">
          {#each awards as award}
            <div class="flex items-baseline gap-4 py-4">
              <span
                class="text-xs font-mono text-primary dark:text-primary-soft shrink-0 w-10"
              >
                {award.year}
              </span>
              <span class="font-medium text-ink dark:text-cloud">{award.name}</span>
            </div>
          {/each}
        </div>
      </div>

      <!-- Awards photo accent — 1/3 -->
      <div class="hidden lg:block">
        <img
          src="/generated/about-awards.png"
          alt="International design award trophies"
          class="w-full rounded-3xl object-cover aspect-square"
          loading="lazy"
        />
      </div>
    </div>

  </div>
</section>
