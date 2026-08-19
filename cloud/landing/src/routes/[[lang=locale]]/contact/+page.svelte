<script lang="ts">
  import ContactPage from '$lib/components/ContactPage.svelte';
  import { defaultLocale } from '$lib/i18n';
  import { page } from '$app/state';

  let lang = $derived((page.params.lang ?? defaultLocale) as string);
</script>

<ContactPage {lang} />
