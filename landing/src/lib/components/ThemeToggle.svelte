<script lang="ts">
  import { theme, toggleTheme } from '$lib/theme';
</script>

<button
  onclick={toggleTheme}
  aria-label="Toggle dark mode"
  class="inline-flex h-8 w-8 items-center justify-center rounded-full border border-ink/10 bg-white/80 text-ink/80 hover:bg-white transition dark:border-white/10 dark:bg-ink/60 dark:text-cloud/80 dark:hover:bg-ink/80"
>
  {#if $theme === 'dark'}
    <!-- Sun -->
    <svg width="14" height="14" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
      <path d="M10 5a5 5 0 110 10 5 5 0 010-10zm0-3a1 1 0 011 1v1a1 1 0 11-2 0V3a1 1 0 011-1zm0 14a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1zM3 9a1 1 0 110 2H2a1 1 0 110-2h1zm15 0a1 1 0 110 2h-1a1 1 0 110-2h1zM4.222 4.222a1 1 0 011.414 0l.707.707a1 1 0 11-1.414 1.414l-.707-.707a1 1 0 010-1.414zm10.435 10.435a1 1 0 011.414 0l.707.707a1 1 0 11-1.414 1.414l-.707-.707a1 1 0 010-1.414zM4.222 15.778a1 1 0 010-1.414l.707-.707a1 1 0 111.414 1.414l-.707.707a1 1 0 01-1.414 0zm10.435-10.435a1 1 0 010-1.414l.707-.707a1 1 0 111.414 1.414l-.707.707a1 1 0 01-1.414 0z" />
    </svg>
  {:else}
    <!-- Moon -->
    <svg width="14" height="14" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
      <path d="M17.293 13.293A8 8 0 016.707 2.707a8.001 8.001 0 1010.586 10.586z" />
    </svg>
  {/if}
</button>
