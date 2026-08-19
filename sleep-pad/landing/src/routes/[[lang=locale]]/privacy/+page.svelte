<script lang="ts">
  import LegalPage from '$lib/components/LegalPage.svelte';
  import { defaultLocale } from '$lib/i18n';
  import { page } from '$app/state';

  let lang = $derived((page.params.lang ?? defaultLocale) as string);
</script>

<LegalPage slug="privacy" {lang} />
