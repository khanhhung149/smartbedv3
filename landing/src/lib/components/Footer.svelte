<script lang="ts">
  import { _ } from 'svelte-i18n';

  const year = new Date().getFullYear();
</script>

<footer class="surface border-t border-ink/10 dark:border-white/10 py-16">
  <div class="container-page">
    <div class="grid md:grid-cols-5 gap-8 mb-12">
      <div class="md:col-span-2">
        <img
          src="/sleep-tech-logo-doc.png"
          alt={$_('brand')}
          class="h-24 w-auto mb-4 dark:invert dark:brightness-200"
          width="120"
          height="160"
        />
        <p class="text-sm text-ink/60 dark:text-cloud/60 leading-relaxed max-w-xs">{$_('footer.tagline')}</p>
      </div>
      <div>
        <h4 class="text-xs font-semibold uppercase tracking-widest text-ink/40 dark:text-cloud/40 mb-3">{$_('footer.links.company')}</h4>
        <ul class="space-y-2 text-sm">
          <li><a href="#about" class="text-ink/70 dark:text-cloud/70 hover:text-ink dark:hover:text-cloud transition">{$_('footer.links.about')}</a></li>
          <li><a href="#" class="text-ink/70 dark:text-cloud/70 hover:text-ink dark:hover:text-cloud transition">{$_('footer.links.press')}</a></li>
          <li><a href="#" class="text-ink/70 dark:text-cloud/70 hover:text-ink dark:hover:text-cloud transition">{$_('footer.links.careers')}</a></li>
        </ul>
      </div>
      <div>
        <h4 class="text-xs font-semibold uppercase tracking-widest text-ink/40 dark:text-cloud/40 mb-3">{$_('footer.links.products')}</h4>
        <ul class="space-y-2 text-sm">
          <li><a href="#products" class="text-ink/70 dark:text-cloud/70 hover:text-ink dark:hover:text-cloud transition">{$_('footer.links.yumepad')}</a></li>
          <li><a href="#products" class="text-ink/70 dark:text-cloud/70 hover:text-ink dark:hover:text-cloud transition">{$_('footer.links.smart_bed')}</a></li>
          <li><a href="#products" class="text-ink/70 dark:text-cloud/70 hover:text-ink dark:hover:text-cloud transition">{$_('footer.links.smart_pillow')}</a></li>
        </ul>
      </div>
      <div>
        <h4 class="text-xs font-semibold uppercase tracking-widest text-ink/40 dark:text-cloud/40 mb-3">{$_('footer.links.legal')}</h4>
        <ul class="space-y-2 text-sm">
          <li><a href="#" class="text-ink/70 dark:text-cloud/70 hover:text-ink dark:hover:text-cloud transition">{$_('footer.links.privacy')}</a></li>
          <li><a href="#" class="text-ink/70 dark:text-cloud/70 hover:text-ink dark:hover:text-cloud transition">{$_('footer.links.terms')}</a></li>
          <li><a href="mailto:hi@sleeptech.me" class="text-ink/70 dark:text-cloud/70 hover:text-ink dark:hover:text-cloud transition">{$_('footer.links.contact')}</a></li>
        </ul>
      </div>
    </div>
    <div class="pt-8 border-t border-ink/10 dark:border-white/10 text-xs text-ink/50 dark:text-cloud/50 flex flex-wrap justify-between gap-3">
      <span>© {year} SleepTech. {$_('footer.rights')}</span>
      <span>hi@sleeptech.me</span>
    </div>
  </div>
</footer>
