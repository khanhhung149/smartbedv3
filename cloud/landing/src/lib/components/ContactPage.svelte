<script lang="ts">
  import { _ } from 'svelte-i18n';
  import { onMount } from 'svelte';
  import Footer from './Footer.svelte';

  let { lang }: { lang: string } = $props();

  // Cloudflare Turnstile site key (public). Validated server-side via the matching secret.
  const TURNSTILE_SITE_KEY = '0x4AAAAAADIyUlo_soNpH-Qp';

  const API_URL = 'https://api.sleeptech.me/contact';

  type State = 'idle' | 'sending' | 'success' | 'error';
  type ErrorKind = 'captcha' | 'ratelimit' | 'generic';

  let state = $state<State>('idle');
  let errorKind = $state<ErrorKind>('generic');

  let name = $state('');
  let email = $state('');
  let subject = $state('');
  let message = $state('');

  let turnstileWidgetId = $state<string | null>(null);
  let turnstileContainer: HTMLDivElement | undefined = $state(undefined);

  // Declare turnstile on window to avoid TS errors
  declare global {
    interface Window {
      turnstile: {
        render: (el: HTMLElement, opts: Record<string, unknown>) => string;
        getResponse: (id: string) => string | null;
        reset: (id: string) => void;
      };
    }
  }

  function mountWidget() {
    if (typeof window === 'undefined' || !window.turnstile || !turnstileContainer) return;
    if (turnstileWidgetId !== null) return; // already mounted
    turnstileWidgetId = window.turnstile.render(turnstileContainer, {
      sitekey: TURNSTILE_SITE_KEY,
      theme: 'auto',
    });
  }

  onMount(() => {
    // Script may already be loaded (e.g. navigating back to page)
    if (window.turnstile) {
      mountWidget();
      return;
    }

    const existing = document.querySelector('script[data-turnstile]');
    if (!existing) {
      const s = document.createElement('script');
      s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js';
      s.async = true;
      s.defer = true;
      s.dataset.turnstile = '1';
      s.onload = () => mountWidget();
      document.head.appendChild(s);
    } else {
      // Script already injected, poll until turnstile is ready
      const interval = setInterval(() => {
        if (window.turnstile) {
          clearInterval(interval);
          mountWidget();
        }
      }, 100);
    }
  });

  async function handleSubmit(e: Event) {
    e.preventDefault();
    if (state === 'sending') return;

    const token =
      turnstileWidgetId !== null ? window.turnstile?.getResponse(turnstileWidgetId) : null;

    state = 'sending';

    try {
      const res = await fetch(API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name,
          email,
          subject,
          message,
          'cf-turnstile-response': token ?? '',
        }),
      });

      if (res.status === 204) {
        state = 'success';
        name = '';
        email = '';
        subject = '';
        message = '';
        if (turnstileWidgetId !== null) window.turnstile?.reset(turnstileWidgetId);
      } else if (res.status === 400) {
        errorKind = 'captcha';
        state = 'error';
        if (turnstileWidgetId !== null) window.turnstile?.reset(turnstileWidgetId);
      } else if (res.status === 429) {
        errorKind = 'ratelimit';
        state = 'error';
      } else {
        errorKind = 'generic';
        state = 'error';
      }
    } catch {
      errorKind = 'generic';
      state = 'error';
    }
  }

  function retry() {
    state = 'idle';
    if (turnstileWidgetId !== null) window.turnstile?.reset(turnstileWidgetId);
  }
</script>

<svelte:head>
  <title>{$_('contact.title')} — SleepTech</title>
</svelte:head>

<article class="surface-alt">
  <div class="container-page py-24 lg:py-32 max-w-3xl">
    <a
      href="/{lang}"
      class="inline-flex items-center text-sm text-primary dark:text-primary-soft hover:underline mb-8"
    >
      {$_('contact.back_to_home')}
    </a>

    <h1 class="text-4xl md:text-5xl font-bold leading-tight mb-6">{$_('contact.title')}</h1>
    <p class="text-lg text-ink/80 dark:text-cloud/80 leading-relaxed mb-12">
      {$_('contact.intro')}
    </p>

    {#if state === 'success'}
      <div
        class="surface-card rounded-2xl p-8 border border-green-200 dark:border-green-800 bg-green-50 dark:bg-green-950/30 text-center"
      >
        <p class="text-2xl font-bold text-green-700 dark:text-green-400 mb-2">
          {$_('contact.success.title')}
        </p>
        <p class="text-ink/70 dark:text-cloud/70">{$_('contact.success.body')}</p>
        <a
          href="/{lang}"
          class="inline-block mt-6 text-sm text-primary dark:text-primary-soft hover:underline"
        >
          {$_('contact.back_to_home')}
        </a>
      </div>
    {:else}
      <form
        onsubmit={handleSubmit}
        class="surface-card rounded-2xl p-8 space-y-6 border border-ink/10 dark:border-white/10"
      >
        {#if state === 'error'}
          <div
            class="rounded-lg px-4 py-3 bg-red-50 dark:bg-red-950/30 border border-red-200 dark:border-red-800 text-red-700 dark:text-red-400 text-sm flex items-start justify-between gap-4"
          >
            <span>{$_(`contact.error.${errorKind}`)}</span>
            <button
              type="button"
              onclick={retry}
              class="shrink-0 underline hover:no-underline"
            >✕</button>
          </div>
        {/if}

        <!-- Name -->
        <div>
          <label for="contact-name" class="block text-sm font-medium mb-1">
            {$_('contact.form.name')}
          </label>
          <input
            id="contact-name"
            type="text"
            bind:value={name}
            placeholder={$_('contact.form.name_placeholder')}
            required
            minlength="1"
            maxlength="100"
            disabled={state === 'sending'}
            class="w-full rounded-lg border border-ink/20 dark:border-white/20 bg-white dark:bg-white/5 px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-primary/50 disabled:opacity-50"
          />
        </div>

        <!-- Email -->
        <div>
          <label for="contact-email" class="block text-sm font-medium mb-1">
            {$_('contact.form.email')}
          </label>
          <input
            id="contact-email"
            type="email"
            bind:value={email}
            placeholder={$_('contact.form.email_placeholder')}
            required
            disabled={state === 'sending'}
            class="w-full rounded-lg border border-ink/20 dark:border-white/20 bg-white dark:bg-white/5 px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-primary/50 disabled:opacity-50"
          />
        </div>

        <!-- Subject -->
        <div>
          <label for="contact-subject" class="block text-sm font-medium mb-1">
            {$_('contact.form.subject')}
          </label>
          <input
            id="contact-subject"
            type="text"
            bind:value={subject}
            placeholder={$_('contact.form.subject_placeholder')}
            required
            minlength="5"
            maxlength="200"
            disabled={state === 'sending'}
            class="w-full rounded-lg border border-ink/20 dark:border-white/20 bg-white dark:bg-white/5 px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-primary/50 disabled:opacity-50"
          />
        </div>

        <!-- Message -->
        <div>
          <label for="contact-message" class="block text-sm font-medium mb-1">
            {$_('contact.form.message')}
          </label>
          <textarea
            id="contact-message"
            bind:value={message}
            placeholder={$_('contact.form.message_placeholder')}
            required
            minlength="10"
            maxlength="2000"
            rows="6"
            disabled={state === 'sending'}
            class="w-full rounded-lg border border-ink/20 dark:border-white/20 bg-white dark:bg-white/5 px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-primary/50 disabled:opacity-50 resize-y"
          ></textarea>
        </div>

        <!-- Turnstile widget — renders only in browser via onMount -->
        <div class="flex flex-col items-center pt-4">
          <p class="text-sm font-medium mb-3 text-center">{$_('contact.form.captcha_label')}</p>
          <!-- Container injected by Turnstile JS at runtime; empty during SSR/prerender -->
          <div bind:this={turnstileContainer} class="flex justify-center"></div>
        </div>

        <!-- Submit (centered) -->
        <div class="flex justify-center pt-2">
          <button
            type="submit"
            disabled={state === 'sending'}
            class="inline-flex items-center justify-center gap-2 rounded-xl bg-primary px-10 py-3 text-sm font-semibold text-white hover:bg-primary/90 disabled:opacity-60 disabled:cursor-not-allowed transition"
          >
            {state === 'sending' ? $_('contact.form.sending') : $_('contact.form.submit')}
          </button>
        </div>
      </form>
    {/if}

  </div>
</article>

<Footer />
