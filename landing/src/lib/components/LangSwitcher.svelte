<script lang="ts">
  import { locales, localeNames, type Locale } from '$lib/i18n';
  import { goto } from '$app/navigation';
  import { page } from '$app/state';

  let { current }: { current: Locale } = $props();
  let open = $state(false);

  function pickLang(loc: Locale) {
    open = false;
    const path = page.url.pathname.replace(/^\/(en|ja|th|vi)?/, '') || '/';
    goto(`/${loc}${path === '/' ? '' : path}`);
  }
</script>

<div class="relative">
  <button
    onclick={() => (open = !open)}
    class="inline-flex items-center gap-1.5 rounded-full border border-ink/10 bg-white/80 px-3 py-1.5 text-xs font-semibold text-ink/80 hover:bg-white transition"
    aria-haspopup="listbox"
    aria-expanded={open}
  >
    <span>{localeNames[current]}</span>
    <svg width="10" height="10" viewBox="0 0 10 10" class:rotate-180={open} class="transition-transform">
      <path d="M2 4l3 3 3-3" stroke="currentColor" stroke-width="1.5" fill="none" />
    </svg>
  </button>
  {#if open}
    <ul
      class="absolute right-0 mt-2 w-40 rounded-xl border border-ink/10 bg-white shadow-xl py-1.5 text-sm overflow-hidden"
      role="listbox"
    >
      {#each locales as loc}
        <li>
          <button
            onclick={() => pickLang(loc)}
            class="w-full text-left px-4 py-2 hover:bg-moon transition"
            class:font-semibold={loc === current}
            class:text-primary={loc === current}
          >
            {localeNames[loc]}
          </button>
        </li>
      {/each}
    </ul>
  {/if}
</div>
