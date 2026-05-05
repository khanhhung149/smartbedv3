/**
 * Generate landing-page hero/product images via Gemini Nano Banana Pro
 * and 1 hero loop video via Veo 3.
 *
 * Default model: gemini-2.5-flash-preview-05-20 (image generation via responseModalities)
 * Falls back to: gemini-2.0-flash-exp if primary returns 404/model-not-found.
 * Imagen helpers kept behind --imagen flag for fallback.
 *
 * Usage:
 *   pnpm gen:images              # generate all images (Banana Pro default)
 *   pnpm gen:images -- --imagen  # use Imagen 4 instead
 *   pnpm gen:avatars
 *   pnpm gen:video
 *   pnpm gen:news-images
 *   pnpm gen:news-inline-images
 *
 * Requires GEMINI_API_KEY in .env.local (see .env.example).
 */
import { GoogleGenAI } from '@google/genai';
import { writeFile, mkdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { config as dotenvConfig } from 'dotenv';

// Load .env.local explicitly (Vite convention, not dotenv default)
dotenvConfig({ path: resolve(import.meta.dirname, '..', '.env.local') });

const apiKey = process.env.GEMINI_API_KEY;
if (!apiKey) {
  console.error('GEMINI_API_KEY missing — copy .env.example to .env.local and fill it.');
  process.exit(1);
}

const ai = new GoogleGenAI({ apiKey });
const ROOT = resolve(import.meta.dirname, '..', 'static', 'generated');

// CLI flag: pass --imagen to use Imagen 4 instead of Banana Pro
const useImagen = process.argv.includes('--imagen');

// Banana Pro model candidates (try in order).
// gemini-3-pro-image-preview = Nano Banana Pro (confirmed working 2026-05-04).
// gemini-3.1-flash-image-preview = fallback if primary is 503/overloaded.
const BANANA_PRO_MODELS = [
  'gemini-3-pro-image-preview',
  'gemini-3.1-flash-image-preview',
];

type ImagePrompt = {
  name: string;
  prompt: string;
  aspectRatio?: '1:1' | '16:9' | '9:16' | '4:3' | '3:4';
};

const PROMPTS: {
  images: ImagePrompt[];
  avatars: ImagePrompt[];
  video: { name: string; prompt: string };
} = {
  images: [
    {
      name: 'hero-bedroom-jp',
      aspectRatio: '16:9',
      prompt:
        'Soft minimalist Japanese bedroom at dawn. Low futon-style bed with a thin smart pad visible underneath the mattress, glowing very faintly with soft indigo light. Tatami floor, shoji screens diffusing warm sunrise light. Soft sakura petals on a wooden side table. Photo-realistic, cinematic, calm. Color palette: deep indigo, off-white, sakura pink accent. No people. No text. 16:9 aspect ratio.'
    },
    {
      name: 'yumepad-product',
      aspectRatio: '4:3',
      prompt:
        'Product photography of a thin sleek sleep monitoring pad lying on a clean off-white sheet, branded subtly with the kanji 夢 in soft indigo. Premium fabric texture, slight quilted pattern. Studio lighting, soft shadows, white background. Apple-product photography aesthetic. No text other than the kanji. 4:3 aspect ratio.'
    },
    {
      name: 'smart-bed',
      aspectRatio: '4:3',
      prompt:
        'Modern minimalist smart bed with subtle curved frame and ambient warm under-bed glow. Japanese-inspired bedroom setting with ash-wood walls, paper lantern, calm pre-dawn atmosphere. Photo-realistic, premium product render, no people, no text. 4:3 aspect ratio.'
    },
    {
      name: 'smart-pillow',
      aspectRatio: '4:3',
      prompt:
        'Premium memory-foam smart pillow on cream linen pillowcase, single light shaft from a side window. Visible thin micro-haptic mesh on side. Studio macro photography, calm muted tones, no people, no text. 4:3 aspect ratio.'
    },
    {
      name: 'family-share-illustration',
      aspectRatio: '16:9',
      prompt:
        'Soft editorial illustration: silhouette of a sleeping figure in one room connected by glowing dotted line to a phone in another room held by a daughter. Indigo and soft pink palette, minimalist line art on cream background. Conveys family care across distance. No text. 16:9 aspect ratio.'
    },
    {
      name: 'about-heritage',
      aspectRatio: '16:9',
      prompt:
        'Photorealistic editorial photo of a multi-generational Japanese family scene — a daughter in her 40s sitting calmly beside her elderly mother (80s) on a tatami floor, soft morning light through shoji screens, a thin smart sleep pad faintly visible under the futon. Warm intimate atmosphere conveying caring across generations. Color palette: deep indigo, off-white, sakura accent. No text, no logos, no watermarks. Documentary photography, 35mm, Asian features authentic. 16:9 aspect ratio.'
    },
    {
      name: 'about-team',
      aspectRatio: '4:3',
      prompt:
        'Photorealistic photo of a small Japanese product-design team in a modern minimalist Tokyo office — three to four professionals (mix of men and women, mid-30s to 50s, authentic Japanese features) leaning over a wooden table examining a thin sleep monitoring pad prototype. Soft natural window light, clean whites and warm wood, calm focused expression on faces. No text on screens or paper. Premium editorial photography, 35mm. 4:3 aspect ratio.'
    },
    {
      name: 'about-awards',
      aspectRatio: '1:1',
      prompt:
        'Premium close-up product photography of two physical award trophies on a dark walnut surface — one a sleek modern glass pyramid award, one a brushed-metal medallion with red ribbon. Soft directional studio lighting from upper-left, deep indigo and gold reflections. Out-of-focus warm bokeh background suggesting an office shelf. No readable text on the awards. Premium luxury product photography. 1:1 square aspect ratio.'
    },
    {
      name: 'about-global',
      aspectRatio: '16:9',
      prompt:
        'Soft editorial illustration: a stylized world map shown in deep indigo on cream paper, with about 20 small glowing sakura-pink dots distributed across Europe, North America, Australia, Japan, Southeast Asia. Subtle dotted lines connecting some points. Minimalist, premium, no country labels, no text. Color palette: indigo, off-white, sakura pink. 16:9 aspect ratio.'
    }
  ],
  avatars: [
    {
      name: 'avatar-aiko',
      aspectRatio: '1:1',
      prompt:
        'Head-and-shoulders portrait photograph of a Japanese woman, mid-30s to early 40s, with authentic East Asian features — slightly rounded face, dark straight hair neatly styled, age-appropriate skin texture with natural micro-imperfections. Genuine calm expression, small warm smile, peaceful and composed — the look of a caring mother. Soft natural window light from the side. Neutral premium background: warm beige or soft off-white, softly blurred. Modern casual-premium attire, muted tones. Photorealistic, 35mm portrait lens bokeh. No text, no logos, no watermarks, no illustration, no anime. 1:1 square aspect ratio.'
    },
    {
      name: 'avatar-linh',
      aspectRatio: '1:1',
      prompt:
        'Head-and-shoulders portrait photograph of a Vietnamese woman, late 20s to mid-30s, with authentic Southeast Asian features — oval face, dark almond-shaped eyes, naturally dark hair, warm medium skin tone, age-appropriate natural skin texture. Gentle warm expression, slightly hopeful and caring smile — the look of a caring daughter. Soft diffused natural light. Neutral premium background: soft warm beige or pale indigo, softly blurred. Modern casual-premium attire, light colors. Photorealistic, shallow depth of field, portrait photography. No text, no logos, no watermarks, no illustration, no anime. 1:1 square aspect ratio.'
    },
    {
      name: 'avatar-somchai',
      aspectRatio: '1:1',
      prompt:
        'Head-and-shoulders portrait photograph of a Thai man, early-to-mid 30s, with authentic Southeast Asian features — broad face, warm olive-brown skin, dark short hair, relaxed confident expression with a casual approachable smile — the look of an easygoing tech-savvy professional. Soft natural indoor light. Neutral premium background: soft off-white or warm sand, softly blurred. Modern casual-premium shirt, dark colors. Photorealistic, 35mm portrait lens bokeh. No text, no logos, no watermarks, no illustration, no anime. 1:1 square aspect ratio.'
    },
    {
      name: 'avatar-hiroshi',
      aspectRatio: '1:1',
      prompt:
        'Head-and-shoulders portrait photograph of a Japanese man, mid-40s to early 50s, with authentic East Asian features — lean angular face, slightly greying short dark hair at temples, refined composed expression with a subtle thoughtful half-smile — the look of a design-appreciating professional, refined but not stiff. Soft directional natural light. Neutral premium background: muted deep indigo or warm off-white, softly blurred. Modern casual-premium attire, dark navy or charcoal. Photorealistic, 35mm portrait lens bokeh. No text, no logos, no watermarks, no illustration, no anime. 1:1 square aspect ratio.'
    }
  ],
  video: {
    name: 'hero-loop',
    prompt:
      'Cinematic seamless 8-second loop. Slow drift over a Japanese tatami bedroom at dawn. Camera glides slowly past a low bed where a thin smart pad pulses softly with a subtle indigo glow under the mattress. Tiny floating sakura petals drift across frame. Warm rising-sun light through shoji screens. No people, no text. Ultra cinematic, calm, premium tech brand vibe. End frame matches start frame for seamless loop.'
  }
};

async function ensureDir(p: string) {
  if (!existsSync(p)) await mkdir(p, { recursive: true });
}

// ─────────────────────────────────────────────────────────────────────────────
// Gemini Nano Banana Pro image generation
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Generate an image via Gemini's native image generation (Nano Banana Pro).
 * Aspect ratio is embedded in the prompt text per Gemini docs.
 * Tries models in BANANA_PRO_MODELS order; falls back on 404/not-found.
 */
async function generateViaBananaPro(prompt: string): Promise<Buffer> {
  let lastErr: Error | undefined;
  for (const model of BANANA_PRO_MODELS) {
    try {
      const response = await ai.models.generateContent({
        model,
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        config: {
          responseModalities: ['Text', 'Image'],
        },
      });
      const parts = response.candidates?.[0]?.content?.parts ?? [];
      const imgPart = parts.find((p) => p.inlineData?.mimeType?.startsWith('image/'));
      if (!imgPart?.inlineData?.data) throw new Error('no image bytes returned');
      const bytes = Buffer.from(imgPart.inlineData.data, 'base64');
      // Log which model succeeded on first success
      if (model !== BANANA_PRO_MODELS[0]) {
        process.stdout.write(`[fallback:${model}] `);
      } else {
        process.stdout.write(`[${model}] `);
      }
      return bytes;
    } catch (err) {
      const msg = (err as Error).message ?? '';
      const isRetryable =
        msg.includes('404') ||
        msg.includes('503') ||
        msg.toLowerCase().includes('not found') ||
        msg.toLowerCase().includes('unavailable') ||
        msg.toLowerCase().includes('high demand');
      lastErr = err as Error;
      if (!isRetryable) throw err; // permanent error: rethrow immediately
      // 404/503 → try next model
      process.stdout.write(`[${model} failed, trying next] `);
    }
  }
  throw lastErr ?? new Error('all Banana Pro models failed');
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared image list generator (supports both Banana Pro and Imagen)
// ─────────────────────────────────────────────────────────────────────────────

async function generateImageList(items: ImagePrompt[], label: string, skipExisting = false) {
  await ensureDir(ROOT);
  const engine = useImagen ? 'Imagen 4' : 'Banana Pro';
  console.log(`Generating ${items.length} ${label} via ${engine} → ${ROOT}/`);
  let retries = 0;
  for (const item of items) {
    const outPath = resolve(ROOT, `${item.name}.png`);
    if (skipExisting && existsSync(outPath)) {
      console.log(`  • ${item.name} — already exists, skipping`);
      continue;
    }
    process.stdout.write(`  • ${item.name} (${item.aspectRatio ?? '16:9'}) ... `);
    let success = false;
    for (let attempt = 1; attempt <= 5; attempt++) {
      try {
        let bytes: Buffer;
        if (useImagen) {
          bytes = await generateViaImagen(item);
        } else {
          bytes = await generateViaBananaPro(item.prompt);
        }
        await writeFile(outPath, bytes);
        console.log(`✓ ${(bytes.length / 1024).toFixed(0)}KB`);
        success = true;
        break;
      } catch (err) {
        if (attempt < 5) {
          const delay = 5000 * attempt; // 5s, 10s, 15s, 20s
          console.error(`\n  attempt ${attempt} failed: ${(err as Error).message.slice(0, 120)}, retrying in ${delay/1000}s…`);
          retries++;
          await new Promise((r) => setTimeout(r, delay));
        } else {
          console.error(`\n  ✗ ${(err as Error).message.slice(0, 120)}`);
        }
      }
    }
    if (!success) {
      console.warn(`  Skipped: ${item.name}`);
    }
  }
  console.log(`Done. Total retries: ${retries}`);
}

// ─────────────────────────────────────────────────────────────────────────────
// Imagen 4 fallback helper (kept for --imagen flag)
// ─────────────────────────────────────────────────────────────────────────────

async function generateViaImagen(item: ImagePrompt): Promise<Buffer> {
  const response = await ai.models.generateImages({
    model: 'imagen-4.0-generate-001',
    prompt: item.prompt,
    config: {
      numberOfImages: 1,
      aspectRatio: item.aspectRatio ?? '1:1',
    },
  });
  const generated = response.generatedImages?.[0];
  if (!generated?.image?.imageBytes) throw new Error('no image bytes returned');
  return Buffer.from(generated.image.imageBytes, 'base64');
}

// ─────────────────────────────────────────────────────────────────────────────
// Public commands
// ─────────────────────────────────────────────────────────────────────────────

async function generateImages() {
  await generateImageList(PROMPTS.images, 'site images');
}

// Kept for compatibility — also routes through generateImageList
async function generateImagesViaImagen() {
  const prev = process.argv;
  process.argv.push('--imagen');
  await generateImageList(PROMPTS.images, 'site images (Imagen 4)');
  process.argv.splice(process.argv.indexOf('--imagen'), 1);
  void prev;
}

async function generateAvatars() {
  await generateImageList(PROMPTS.avatars, 'avatars');
}

async function generateVideo() {
  await ensureDir(ROOT);
  const outPath = resolve(ROOT, `${PROMPTS.video.name}.mp4`);
  console.log(`Generating Veo 3 video → ${outPath}`);
  console.log(`Prompt: ${PROMPTS.video.prompt}`);
  try {
    let operation = await ai.models.generateVideos({
      model: 'veo-3.0-generate-001',
      prompt: PROMPTS.video.prompt,
      config: {
        aspectRatio: '16:9',
        numberOfVideos: 1
      }
    });
    process.stdout.write('Polling');
    while (!operation.done) {
      process.stdout.write('.');
      await new Promise((r) => setTimeout(r, 10_000));
      operation = await ai.operations.getVideosOperation({ operation });
    }
    console.log(' done.');
    const video = operation.response?.generatedVideos?.[0]?.video;
    if (!video) throw new Error('no video returned');
    await ai.files.download({ file: video, downloadPath: outPath });
    console.log(`✓ saved ${outPath}`);
  } catch (err) {
    console.error(`✗ ${(err as Error).message}`);
    process.exit(1);
  }
}

const NEWS_IMAGE_PROMPTS: ImagePrompt[] = [
  // ── Inline images (2 per article, 5 articles = 10 total) ──────────────────
  {
    name: 'news-how-ai-revolutionizes-sleep-monitoring-inline-1',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: an AI data-visualization dashboard floating holographically above a thin sleep pad on a premium Japanese bed. Glowing indigo neural-network nodes and soft waveforms representing REM and deep-sleep stages. Dark atmospheric background, sakura-pink accent highlights. Photorealistic, cinematic, premium tech editorial. No text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-how-ai-revolutionizes-sleep-monitoring-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Macro editorial photo: a cross-section layered view of a mattress with a gossamer-thin sensor pad embedded inside, soft indigo light tracing signal pathways through the layers. Abstract yet scientific, premium editorial photography aesthetic. Deep indigo and off-white palette. No text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-heart-rate-variability-explained-inline-1',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo concept: a glowing HRV waveform (inter-beat intervals shown as a rhythmic oscillating curve) rendered as soft light on dark premium fabric surface. The peaks pulse gently between indigo and sakura pink, conveying calm parasympathetic dominance. No people, no text, no logos, no watermarks. Premium scientific editorial photography. 16:9 aspect ratio.'
  },
  {
    name: 'news-heart-rate-variability-explained-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial illustration-photo: a circular HRV frequency spectrum wheel rendered as a glowing mandala in deep indigo and sakura pink — the center calm, outer edges representing low-frequency stress signatures. Scientific beauty, abstract editorial, premium dark background. No text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-wearables-vs-non-contact-sensors-inline-1',
    aspectRatio: '16:9',
    prompt:
      'Editorial close-up photo of a smartwatch on a wrist resting on white linen pillow, soft sleep environment context. Premium product photography, shallow depth of field, warm side light. The watch face dark/sleep mode. Off-white and warm silver palette. No text on screen, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-wearables-vs-non-contact-sensors-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: under-mattress view concept — a thin translucent sensor pad between mattress layers, soft indigo LED trace lines mapping body zones. An X-ray style illustrative overlay on a real bedroom environment. Premium health-tech editorial, calm scientific mood. No text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-privacy-first-sleep-ai-inline-1',
    aspectRatio: '16:9',
    prompt:
      'Editorial concept photo: microscopic data particles swirling inside a transparent glass sphere, contained and protected. Deep indigo and soft gold tones, privacy-as-containment metaphor. Dark premium background, editorial science photography aesthetic. No text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-privacy-first-sleep-ai-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: a minimalist Japanese bedroom at night, the smart sleep pad glowing with soft indigo, but all data represented as particles dissolving and disappearing before reaching the wall — a visual metaphor for edge-only processing. No cloud connection visible. Cinematic, premium. No text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-ballistocardiography-future-sleep-tech-inline-1',
    aspectRatio: '16:9',
    prompt:
      'Editorial macro photo: slow-motion water surface ripple pattern on deep indigo liquid, shot from above — a visual metaphor for the micro-vibrations that ballistocardiography captures. Each concentric ring a heartbeat. Premium editorial photography, clean abstract. No text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-ballistocardiography-future-sleep-tech-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial illustration-photo: a phantom human silhouette lying on a smart sleep pad, with a luminous ballistic waveform (J-wave, K-wave peaks) traced over the body in soft indigo and sakura light. Scientific anatomy meets premium design. Dark background, cinematic depth of field. No text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  // ── Inline images articles 6-10 ───────────────────────────────────────────
  {
    name: 'news-realtime-vital-alerts-balance-inline-1',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo of a smartphone on a wooden bedside table, screen glowing softly with a minimal notification badge in soft green, a thin smart sleep pad visible at the bed edge, dim ambient indigo light filling the room. Photorealistic, calm bedroom mood, no alarm urgency. No text on screen, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-realtime-vital-alerts-balance-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial illustration-photo: an abstract escalating tier of soft glowing rings — the innermost ring small and calm indigo, middle ring soft amber, outer ring barely visible sakura pink — representing alert escalation tiers. Dark premium background, minimalist scientific design, no text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-sleep-apnea-detection-at-home-inline-1',
    aspectRatio: '16:9',
    prompt:
      'Photorealistic editorial close-up of a sleeping man on a cream pillow, soft pre-dawn indigo light from the window, peaceful expression, shallow depth of field. Documentary photography quality. No clinical equipment visible, no text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-sleep-apnea-detection-at-home-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial concept photo: a breath-rate waveform — shown as smooth glowing light arcs against dark background — with a subtle interruption gap in the middle representing an apnea pause, then resuming. Indigo and soft sakura palette, abstract scientific, premium editorial. No text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-sustainable-sleep-routine-with-data-inline-1',
    aspectRatio: '16:9',
    prompt:
      'Editorial lifestyle photo: a minimal weekly sleep trend chart shown on a smartphone screen sitting beside a morning cup of matcha on a wooden desk, warm dawn light through a Japanese window. Photorealistic, calm productive morning mood. No readable text on screen, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-sustainable-sleep-routine-with-data-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: a peaceful Japanese bedroom in the morning, warm sunlight through shoji screens, neatly folded futon with a thin sleep pad placed on top, a small plant beside the window. Implies a consistent calming routine. Photorealistic, warm tones. No people, no text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-hrv-and-sleep-quality-inline-1',
    aspectRatio: '16:9',
    prompt:
      'Editorial macro photo: a glowing HRV recovery score graph — a gentle upward-trending curve in soft indigo on dark background, with a calm peak labeled by a soft sakura-pink dot. No numbers, no text. Abstract data visualization as art. Premium editorial, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-hrv-and-sleep-quality-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial split photo concept: left side shows a glass of red wine on a nightstand with a slightly suppressed HRV waveform above it in amber glow; right side shows a glass of water with a higher, healthier HRV waveform in indigo. Symbolic lifestyle comparison, no text, no logos, no watermarks. Premium studio photography. 16:9 aspect ratio.'
  },
  {
    name: 'news-bedroom-climate-and-sleep-stages-inline-1',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: a Japanese minimalist bedroom at night with cool blue moonlight through shoji screens, crisp white linen on a low bed, a soft temperature display glowing on the wall showing a comfortable cool reading. Calm, premium, cinematic. No text on display, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-bedroom-climate-and-sleep-stages-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial concept photo: a cross-section diagram of sleep stages shown as layered glowing bands — deep blue for slow-wave sleep, amber for REM, soft indigo for light sleep — with a temperature gradient color overlay showing cooler temperatures correlating with deeper blue stages. Abstract scientific art, premium dark background, no text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  // ── Inline images articles 11-15 ─────────────────────────────────────────
  {
    name: 'news-snoring-detection-with-ai-inline-1',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo of a tilted minimalist memory-foam pillow with a faintly glowing micro-mesh sensor edge, soft indigo studio light, premium product photography. No text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-snoring-detection-with-ai-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial concept photo: abstract acoustic waveforms rendered as glowing indigo arcs floating above a dark bedroom pillow surface — the waves progress from jagged rough snore patterns on the left to smooth sinusoidal sleep waves on the right, symbolizing AI-assisted snoring detection and correction. Cinematic, premium, no faces, no text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-mindful-pre-sleep-routines-with-data-inline-1',
    aspectRatio: '16:9',
    prompt:
      'Editorial lifestyle photo: a Japanese ofuro (deep soaking bath) with steam rising, soft warm lamplight, a wooden tray with a single candle and folded towel resting on the edge. Tranquil pre-sleep ritual atmosphere. Photorealistic, warm amber and off-white tones, no people, no text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-mindful-pre-sleep-routines-with-data-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: a smartphone resting on a low wooden bedside table displaying a minimal circular wind-down progress tracker glowing softly in indigo — T-90/T-60/T-30 segments shown as arcs, no readable text. A single burning candle and a closed book beside it. Photorealistic, calm evening mood, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-tracking-elderly-sleep-patterns-inline-1',
    aspectRatio: '16:9',
    prompt:
      'Editorial macro photo: a thin translucent sleep sensor pad lying flat on cream Japanese futon fabric, faint indigo light tracing a body-zone silhouette on the pad surface. Soft natural morning light from the side. Premium product editorial, no people, no text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-tracking-elderly-sleep-patterns-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: an elderly Japanese woman (80s) and her adult daughter (50s) sitting calmly together at a low wooden table, a smartphone between them displaying a gentle sleep trend graph in soft indigo — an intimate, dignified conversation about health. Documentary warmth, authentic Asian features, no readable text on screen, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-shift-workers-sleep-strategies-inline-1',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: a nurse in scrubs arriving home at dawn, pulling thick blackout curtains closed across a window where sunrise light edges through. A smart sleep pad glows softly indigo on the bed behind her. Empathetic, cinematic, photorealistic. No text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-shift-workers-sleep-strategies-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial concept photo: a dual-exposure composition — one half shows a city under blazing midday sun (busy street, people moving), the other half shows a darkened bedroom with blackout curtains and a peacefully sleeping figure under soft indigo light. A visual metaphor for circadian disruption. Cinematic editorial split, no text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-caring-from-afar-night-monitoring-inline-1',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: a woman in her 40s checking her smartphone with a calm, relieved expression at her kitchen table in early morning, a cup of coffee nearby. Through a soft-focus background, the implication of distance — a cozy, separate home visible through a window. Warm tones, photorealistic, authentic Asian features. No text on screen, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-caring-from-afar-night-monitoring-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial soft illustration-photo: an elderly woman sleeping peacefully in a Japanese bedroom, a thin smart pad glowing faintly under her futon. A glowing dotted-light arc connects from the room outward through the wall — symbolizing a quiet data connection to a distant family member. Indigo and sakura-pink tones, intimate and safe mood, no text, no logos, no watermarks. 16:9 aspect ratio.'
  },
  // ── Articles 16-20 inline images ─────────────────────────────────────────
  {
    name: 'news-bed-presence-detection-fall-prevention-inline-1',
    aspectRatio: '16:9',
    prompt:
      "Editorial photo concept: a Japanese bedroom at night seen from slightly above, an elderly person's silhouette beginning to sit up in bed, a subtle safety glow around the bed edge, smart sensor light glowing blue-indigo. Protective, caring mood. No text, no logos, no watermarks. Photorealistic, deep indigo and off-white palette. 16:9 aspect ratio."
  },
  {
    name: 'news-bed-presence-detection-fall-prevention-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: a smartphone on a bedside table with warm lamp light, displaying a soft minimal alert notification showing bed-exit time and elapsed absence duration. Japanese minimalist bedroom background, peaceful early morning mood. No readable text on screen, no logos, no watermarks. Photorealistic. 16:9 aspect ratio.'
  },
  {
    name: 'news-caring-elders-japan-tradition-meets-ai-inline-1',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: a daughter in her 40s and her elderly mother (80s) sitting together in a traditional Japanese tatami room, soft shoji morning light, a smartphone showing a calm sleep report resting between them on the floor. Warm oyakoko filial devotion mood, photorealistic documentary. Authentic Asian features, no readable text on phone, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-caring-elders-japan-tradition-meets-ai-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: a thin YumePad sleep sensor pad barely visible tucked under a futon mattress in a traditional Japanese bedroom with tatami flooring and shoji screen panels. Soft dawn light, deep indigo and off-white palette, calm and unobtrusive mood. No people, no text, no logos, no watermarks. Photorealistic wabi-sabi aesthetic. 16:9 aspect ratio.'
  },
  {
    name: 'news-yumepad-first-night-setup-elderly-parent-inline-1',
    aspectRatio: '16:9',
    prompt:
      "Editorial photo: a son in his early 40s gently and carefully sliding a thin sleep monitoring pad under his elderly father's mattress in a warm Japanese bedroom with soft lamp lighting. The gesture is gentle and respectful. Documentary warmth, photorealistic, authentic Asian features. No text, no logos, no watermarks. 16:9 aspect ratio."
  },
  {
    name: 'news-yumepad-first-night-setup-elderly-parent-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: a close-up of a smartphone screen showing a SleepTech app first-night baseline learning progress screen with a soft progress ring and a gentle reassurance message, all in warm indigo and off-white tones. Phone resting on a wooden bedside table. No readable text, no logos, no watermarks. Photorealistic soft product photography. 16:9 aspect ratio.'
  },
  {
    name: 'news-real-family-stories-peace-of-mind-inline-1',
    aspectRatio: '16:9',
    prompt:
      "Editorial photo: a woman in her late 40s smiling warmly at her smartphone screen in early morning soft light, a cup of coffee nearby on a kitchen table. The screen glow suggests a reassuring sleep report. Warm, peaceful, connected mood. Photorealistic, authentic Asian features. No readable text on screen, no logos, no watermarks. 16:9 aspect ratio."
  },
  {
    name: 'news-real-family-stories-peace-of-mind-inline-2',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: a professional care coordinator (woman, 40s) calmly reviewing a tablet showing multiple soft sleep summary cards in a warm, organized office. Calm focused expression conveying reassurance rather than alarm. Premium editorial, photorealistic, authentic Asian features. No readable text on screen, no logos, no watermarks. 16:9 aspect ratio.'
  },
  {
    name: 'news-nighttime-caregiver-burden-tech-relief-inline-1',
    aspectRatio: '16:9',
    prompt:
      "Editorial photo: an exhausted female caregiver (50s) resting in a comfortable chair beside an elderly relative's bed at night, but her posture is relaxed — a smartphone on the side table shows a calm vital-sign readout in soft green light. The technology has given her permission to rest. Empathetic, warm mood. Photorealistic, no text, no logos, no watermarks. 16:9 aspect ratio."
  },
  {
    name: 'news-nighttime-caregiver-burden-tech-relief-inline-2',
    aspectRatio: '16:9',
    prompt:
      "Editorial photo: a woman caregiver sleeping peacefully in her own comfortable bed, a smartphone on the bedside table displaying a soft green peaceful vital-sign indicator from her elderly relative's room. The scene conveys earned rest and trust in monitoring technology. Warm bedroom tones, photorealistic. No text, no logos, no watermarks. 16:9 aspect ratio."
  },
  // ── Feature/hero images (one per article, per article page) ───────────────
  {
    name: 'news-how-ai-revolutionizes-sleep-monitoring',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo of a thin sleep monitoring pad on a soft bed with subtle indigo data visualization overlaid as light rays, floating waveform patterns representing heart rate and breath. Photorealistic, calm, premium tech editorial, deep indigo and off-white palette. No text, no logos, no watermarks. 16:9 aspect ratio.',
  },
  {
    name: 'news-heart-rate-variability-explained',
    aspectRatio: '16:9',
    prompt:
      'Close-up editorial macro photo of a glowing blue-indigo heartbeat waveform projected onto the surface of a premium dark fabric. Cinematic depth of field, sakura-pink accent highlights on wave peaks. No people, no text, no logos. Photorealistic premium tech. 16:9 aspect ratio.',
  },
  {
    name: 'news-wearables-vs-non-contact-sensors',
    aspectRatio: '16:9',
    prompt:
      'Editorial split composition: left side shows a smartwatch on a wrist on white linen; right side shows a thin sleep pad under a mattress with faint indigo glow. Clean neutral background, premium product photography, soft studio lighting. No text, no logos. 16:9 aspect ratio.',
  },
  {
    name: 'news-privacy-first-sleep-ai',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo concept: a glowing padlock formed from soft light resting on a minimalist Japanese bedroom nightstand, indigo ambient light, data particles dissolving into the air and stopping at a room boundary. Photorealistic, calm, premium. No text, no logos. 16:9 aspect ratio.',
  },
  {
    name: 'news-ballistocardiography-future-sleep-tech',
    aspectRatio: '16:9',
    prompt:
      'Macro editorial photo of a cross-section diagram rendered as glowing light on dark fabric — subtle heartbeat mechanical wave ripples emanating from a thin pad under premium mattress fabric. Deep indigo tones, soft sakura accents. Photorealistic editorial. No text, no logos. 16:9 aspect ratio.',
  },
  {
    name: 'news-realtime-vital-alerts-balance',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: a smartphone on a bedside table showing a calm, minimal sleep dashboard with soft green vital-sign indicators. Japanese minimalist bedroom background, pre-dawn light through shoji screen. Photorealistic, peaceful mood. No text on screen, no logos. 16:9 aspect ratio.',
  },
  {
    name: 'news-sleep-apnea-detection-at-home',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: a person sleeping peacefully in a dark Japanese bedroom, a thin smart pad glowing faintly indigo under the mattress, soft breathing indicator light pulsing. Warm intimate documentary photography, no clinical equipment visible. No text, no logos. 16:9 aspect ratio.',
  },
  {
    name: 'news-sustainable-sleep-routine-with-data',
    aspectRatio: '16:9',
    prompt:
      'Editorial lifestyle photo: a morning journal open on a wooden desk next to a smartphone showing a minimal sleep chart, a steaming cup of tea, warm dawn light. Japanese minimalist interior, off-white and warm wood tones. Photorealistic. No readable text, no logos. 16:9 aspect ratio.',
  },
  {
    name: 'news-hrv-and-sleep-quality',
    aspectRatio: '16:9',
    prompt:
      'Editorial illustration-photo hybrid: a glowing double helix or feedback loop formed from soft indigo light and sakura-pink accents, representing the bidirectional relationship between sleep and heart rate variability. Dark premium background, science editorial aesthetic. No text, no logos. 16:9 aspect ratio.',
  },
  {
    name: 'news-bedroom-climate-and-sleep-stages',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: a cozy Japanese minimalist bedroom at night, subtle cool-blue moonlight through shoji, a smart thermostat glowing softly on the wall, crisp white linen, temperature fog effect near the floor. Cinematic, premium, calm. No text, no logos. 16:9 aspect ratio.',
  },
  {
    name: 'news-snoring-detection-with-ai',
    aspectRatio: '16:9',
    prompt:
      'Editorial concept photo: abstract sound waveforms in soft indigo light floating above a sleeping figure silhouette in a Japanese bedroom. The waves transform from rough snore patterns to smooth sleep waves. No faces visible, artistic, premium. No text, no logos. 16:9 aspect ratio.',
  },
  {
    name: 'news-mindful-pre-sleep-routines-with-data',
    aspectRatio: '16:9',
    prompt:
      'Editorial lifestyle photo: a woman sitting cross-legged on a Japanese bedroom floor in soft lamplight, eyes closed in meditation, a sleep pad glowing softly under the nearby futon, warm sakura-pink and indigo ambient tones. Photorealistic, calm, premium. No text, no logos. 16:9 aspect ratio.',
  },
  {
    name: 'news-tracking-elderly-sleep-patterns',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: an elderly Japanese woman (80s) sleeping peacefully in a traditional Japanese bedroom, soft morning light through shoji screens, a thin smart pad visible under her futon mattress with faint indigo glow. Documentary warmth, intimate, respectful framing. No text, no logos. 16:9 aspect ratio.',
  },
  {
    name: 'news-shift-workers-sleep-strategies',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: a tired nurse or worker arriving home at dawn pulling blackout curtains closed, a smart sleep pad visible on the bed, circadian clock concept with day and night blending through the window. Photorealistic, empathetic mood. No text, no logos. 16:9 aspect ratio.',
  },
  {
    name: 'news-caring-from-afar-night-monitoring',
    aspectRatio: '16:9',
    prompt:
      "Editorial photo: a woman in her 40s checking her phone with a peaceful expression while her elderly mother sleeps in another room visible through soft focus in the background. Warm intimate tones, a care-at-distance theme. Photorealistic, Asian features. No text, no logos. 16:9 aspect ratio.",
  },
  {
    name: 'news-bed-presence-detection-fall-prevention',
    aspectRatio: '16:9',
    prompt:
      "Editorial photo concept: a Japanese bedroom at night seen from slightly above, an elderly person's silhouette beginning to sit up in bed, a subtle safety glow around the bed edge, smart sensor light glowing blue-indigo. Protective, caring mood. No text, no logos. 16:9 aspect ratio.",
  },
  {
    name: 'news-caring-elders-japan-tradition-meets-ai',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: a daughter (40s) and her elderly mother (80s) sitting together in a traditional Japanese room, soft tatami and shoji light, a smartphone showing a sleep report between them. Warm oyakoko filial devotion mood, photorealistic documentary. No text on phone, no logos. 16:9 aspect ratio.',
  },
  {
    name: 'news-yumepad-first-night-setup-elderly-parent',
    aspectRatio: '16:9',
    prompt:
      "Editorial photo: a son in his 40s gently placing a thin sleep monitoring pad under his elderly father's mattress in a Japanese bedroom, warm soft lamp light, careful and gentle gesture. Documentary warmth, photorealistic, authentic Asian features. No text, no logos. 16:9 aspect ratio.",
  },
  {
    name: 'news-real-family-stories-peace-of-mind',
    aspectRatio: '16:9',
    prompt:
      'Editorial photo: a collage-style composition of three moments — a woman smiling at her phone at dawn, an elderly person sleeping peacefully, a family video call on a tablet in a warm living room. Warm connected family mood, photorealistic. No text, no logos. 16:9 aspect ratio.',
  },
  {
    name: 'news-nighttime-caregiver-burden-tech-relief',
    aspectRatio: '16:9',
    prompt:
      "Editorial photo: an exhausted caregiver (woman, 50s) sitting in a chair next to an elderly relative's bed at night, but relaxed — a smartphone on the side table shows a peaceful vital-sign readout in soft green. The technology has given her permission to rest. Empathetic mood, photorealistic. No text, no logos. 16:9 aspect ratio.",
  },
];

async function generateNewsImages() {
  await generateImageList(NEWS_IMAGE_PROMPTS, 'news feature images');
}

async function generateNewsInlineImages() {
  const inlinePrompts = NEWS_IMAGE_PROMPTS.filter((p) => p.name.includes('-inline-'));
  await generateImageList(inlinePrompts, 'news inline images', true);
}

// ─────────────────────────────────────────────────────────────────────────────
// CLI dispatch
// ─────────────────────────────────────────────────────────────────────────────

// argv[0] = node, argv[1] = script path, argv[2] = command
const cmd = process.argv[2];
if (cmd === 'images') generateImages();
else if (cmd === 'avatars') generateAvatars();
else if (cmd === 'video') generateVideo();
else if (cmd === 'news-images') generateNewsImages();
else if (cmd === 'news-inline-images') generateNewsInlineImages();
else {
  console.error('Usage: tsx scripts/generate-assets.ts <images|avatars|video|news-images|news-inline-images> [--imagen]');
  process.exit(1);
}
