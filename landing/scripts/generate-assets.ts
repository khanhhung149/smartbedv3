/**
 * Generate landing-page hero/product images via Google AI (Imagen 4 / Nano Banana Pro)
 * and 1 hero loop video via Veo 3.
 *
 * Usage:
 *   pnpm gen:images   # generate all images defined in PROMPTS.images
 *   pnpm gen:video    # generate hero video defined in PROMPTS.video
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

type ImagePrompt = {
  name: string;
  prompt: string;
  aspectRatio?: '1:1' | '16:9' | '9:16' | '4:3' | '3:4';
};

const PROMPTS: { images: ImagePrompt[]; video: { name: string; prompt: string } } = {
  images: [
    {
      name: 'hero-bedroom-jp',
      aspectRatio: '16:9',
      prompt:
        'Soft minimalist Japanese bedroom at dawn. Low futon-style bed with a thin smart pad visible underneath the mattress, glowing very faintly with soft indigo light. Tatami floor, shoji screens diffusing warm sunrise light. Soft sakura petals on a wooden side table. Photo-realistic, cinematic, calm. Color palette: deep indigo, off-white, sakura pink accent. No people. No text.'
    },
    {
      name: 'yumepad-product',
      aspectRatio: '4:3',
      prompt:
        'Product photography of a thin sleek sleep monitoring pad lying on a clean off-white sheet, branded subtly with the kanji 夢 in soft indigo. Premium fabric texture, slight quilted pattern. Studio lighting, soft shadows, white background. Apple-product photography aesthetic. No text other than the kanji.'
    },
    {
      name: 'smart-bed',
      aspectRatio: '4:3',
      prompt:
        'Modern minimalist smart bed with subtle curved frame and ambient warm under-bed glow. Japanese-inspired bedroom setting with ash-wood walls, paper lantern, calm pre-dawn atmosphere. Photo-realistic, premium product render, no people, no text.'
    },
    {
      name: 'smart-pillow',
      aspectRatio: '4:3',
      prompt:
        'Premium memory-foam smart pillow on cream linen pillowcase, single light shaft from a side window. Visible thin micro-haptic mesh on side. Studio macro photography, calm muted tones, no people, no text.'
    },
    {
      name: 'family-share-illustration',
      aspectRatio: '16:9',
      prompt:
        'Soft editorial illustration: silhouette of a sleeping figure in one room connected by glowing dotted line to a phone in another room held by a daughter. Indigo and soft pink palette, minimalist line art on cream background. Conveys family care across distance. No text.'
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

async function generateImages() {
  await ensureDir(ROOT);
  console.log(`Generating ${PROMPTS.images.length} images → ${ROOT}/`);
  for (const item of PROMPTS.images) {
    const outPath = resolve(ROOT, `${item.name}.png`);
    process.stdout.write(`  • ${item.name} (${item.aspectRatio ?? '1:1'}) ... `);
    try {
      const response = await ai.models.generateImages({
        model: 'imagen-4.0-generate-001',
        prompt: item.prompt,
        config: {
          numberOfImages: 1,
          aspectRatio: item.aspectRatio ?? '1:1'
        }
      });
      const generated = response.generatedImages?.[0];
      if (!generated?.image?.imageBytes) throw new Error('no image bytes returned');
      const bytes = Buffer.from(generated.image.imageBytes, 'base64');
      await writeFile(outPath, bytes);
      console.log(`✓ ${(bytes.length / 1024).toFixed(0)}KB`);
    } catch (err) {
      console.error(`✗ ${(err as Error).message}`);
    }
  }
  console.log('Done.');
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

const cmd = process.argv[2];
if (cmd === 'images') generateImages();
else if (cmd === 'video') generateVideo();
else {
  console.error('Usage: tsx scripts/generate-assets.ts <images|video>');
  process.exit(1);
}
