<script lang="ts">
  import { _, json } from 'svelte-i18n';

  type Product = {
    name: string;
    kanji?: string;
    subtitle?: string;
    tagline: string;
    description: string;
    features?: string[];
    status: string;
    cta: string;
  };

  const empty: Product = { name: '', tagline: '', description: '', status: '', cta: '', features: [] };
  let yume = $derived(($json('products.items.yumepad') as Product) ?? empty);
  let bed = $derived(($json('products.items.smart_bed') as Product) ?? empty);
  let pillow = $derived(($json('products.items.smart_pillow') as Product) ?? empty);
</script>

<section id="products" class="section bg-cloud">
  <div class="container-page">
    <div class="max-w-3xl mb-16">
      <div class="kicker">{$_('products.kicker')}</div>
      <h2 class="text-4xl md:text-5xl font-bold leading-tight mb-6">{$_('products.title')}</h2>
      <p class="text-lg text-ink/70">{$_('products.lead')}</p>
    </div>

    <!-- Hero product: YumePad -->
    <article class="rounded-[2.5rem] bg-gradient-to-br from-ink to-primary-dark text-white mb-6 relative overflow-hidden">
      <div class="absolute -top-20 -right-20 w-96 h-96 rounded-full bg-sakura/20 blur-3xl"></div>
      <div class="absolute top-10 right-10 text-[12rem] leading-none font-jp opacity-10 select-none pointer-events-none">
        {yume.kanji}
      </div>
      <div class="relative grid lg:grid-cols-2 gap-0 items-stretch">
        <div class="p-10 md:p-16">
          <span class="inline-block px-3 py-1 rounded-full bg-sakura/20 text-sakura text-xs font-semibold mb-4">
            {yume.status}
          </span>
          <div class="flex items-baseline gap-3 mb-2">
            <h3 class="text-5xl md:text-6xl font-bold tracking-tight">{yume.name}</h3>
            <span class="text-sm font-medium text-white/60">{yume.subtitle}</span>
          </div>
          <p class="text-xl md:text-2xl text-white/80 mb-6 italic">{yume.tagline}</p>
          <p class="text-white/70 leading-relaxed mb-8 max-w-xl">{yume.description}</p>
          <div class="text-xs uppercase tracking-widest text-white/40 mb-4">
            {$_('products.common.key_features')}
          </div>
          <ul class="space-y-2.5 mb-8">
            {#each yume.features ?? [] as f}
              <li class="flex gap-3 text-white/85 text-sm">
                <svg class="w-4 h-4 mt-1 flex-none text-sakura" viewBox="0 0 20 20" fill="currentColor">
                  <path d="M16.7 5.3a1 1 0 010 1.4l-7 7a1 1 0 01-1.4 0l-3-3a1 1 0 011.4-1.4L9 11.6l6.3-6.3a1 1 0 011.4 0z" />
                </svg>
                <span>{f}</span>
              </li>
            {/each}
          </ul>
          <a href="#cta" class="inline-flex items-center justify-center rounded-full bg-white text-ink px-6 py-3 text-sm font-semibold hover:bg-cloud transition">
            {yume.cta}
          </a>
        </div>
        <div class="relative min-h-[400px] lg:min-h-full">
          <img
            src="/generated/yumepad-product.png"
            alt={yume.name}
            class="absolute inset-0 w-full h-full object-cover"
            loading="lazy"
          />
          <div class="absolute inset-0 bg-gradient-to-l from-transparent to-ink/40 lg:to-ink/20"></div>
        </div>
      </div>
    </article>

    <!-- Smart Bed + Smart Pillow side-by-side -->
    <div class="grid md:grid-cols-2 gap-6">
      {#each [{ p: bed, img: '/generated/smart-bed.png' }, { p: pillow, img: '/generated/smart-pillow.png' }] as { p, img }}
        <article class="rounded-3xl bg-white border border-ink/10 overflow-hidden hover:border-primary/30 hover:shadow-lg transition flex flex-col">
          <div class="relative aspect-[4/3] overflow-hidden bg-moon">
            <img src={img} alt={p.name} class="absolute inset-0 w-full h-full object-cover" loading="lazy" />
          </div>
          <div class="p-8 flex-1 flex flex-col">
            <span class="inline-block px-2.5 py-1 rounded-full bg-moon text-ink/60 text-xs font-semibold mb-4 self-start">
              {p.status}
            </span>
            <h3 class="text-2xl font-bold mb-2">{p.name}</h3>
            <p class="text-ink/70 italic mb-4">{p.tagline}</p>
            <p class="text-ink/60 leading-relaxed mb-6 text-sm flex-1">{p.description}</p>
            <a href="#cta" class="text-sm font-semibold text-primary hover:text-primary-dark transition self-start">
              {p.cta} →
            </a>
          </div>
        </article>
      {/each}
    </div>
  </div>
</section>
