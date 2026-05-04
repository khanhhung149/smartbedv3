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
    },
    {
      name: 'about-heritage',
      aspectRatio: '16:9',
      prompt:
        'Photorealistic editorial photo of a multi-generational Japanese family scene — a daughter in her 40s sitting calmly beside her elderly mother (80s) on a tatami floor, soft morning light through shoji screens, a thin smart sleep pad faintly visible under the futon. Warm intimate atmosphere conveying caring across generations. Color palette: deep indigo, off-white, sakura accent. No text, no logos, no watermarks. Documentary photography, 35mm, Asian features authentic.'
    },
    {
      name: 'about-team',
      aspectRatio: '4:3',
      prompt:
        'Photorealistic photo of a small Japanese product-design team in a modern minimalist Tokyo office — three to four professionals (mix of men and women, mid-30s to 50s, authentic Japanese features) leaning over a wooden table examining a thin sleep monitoring pad prototype. Soft natural window light, clean whites and warm wood, calm focused expression on faces. No text on screens or paper. Premium editorial photography, 35mm.'
    },
    {
      name: 'about-awards',
      aspectRatio: '1:1',
      prompt:
        'Premium close-up product photography of two physical award trophies on a dark walnut surface — one a sleek modern glass pyramid award, one a brushed-metal medallion with red ribbon. Soft directional studio lighting from upper-left, deep indigo and gold reflections. Out-of-focus warm bokeh background suggesting an office shelf. No readable text on the awards. Premium luxury product photography.'
    },
    {
      name: 'about-global',
      aspectRatio: '16:9',
      prompt:
        'Soft editorial illustration: a stylized world map shown in deep indigo on cream paper, with about 20 small glowing sakura-pink dots distributed across Europe, North America, Australia, Japan, Southeast Asia. Subtle dotted lines connecting some points. Minimalist, premium, no country labels, no text. Color palette: indigo, off-white, sakura pink.'
    }
  ],
  avatars: [
    {
      name: 'avatar-aiko',
      aspectRatio: '1:1',
      prompt:
        'Head-and-shoulders portrait photograph of a Japanese woman, mid-30s to early 40s, with authentic East Asian features — slightly rounded face, dark straight hair neatly styled, age-appropriate skin texture with natural micro-imperfections. Genuine calm expression, small warm smile, peaceful and composed — the look of a caring mother. Soft natural window light from the side. Neutral premium background: warm beige or soft off-white, softly blurred. Modern casual-premium attire, muted tones. Photorealistic, 35mm portrait lens bokeh. No text, no logos, no watermarks, no illustration, no anime.'
    },
    {
      name: 'avatar-linh',
      aspectRatio: '1:1',
      prompt:
        'Head-and-shoulders portrait photograph of a Vietnamese woman, late 20s to mid-30s, with authentic Southeast Asian features — oval face, dark almond-shaped eyes, naturally dark hair, warm medium skin tone, age-appropriate natural skin texture. Gentle warm expression, slightly hopeful and caring smile — the look of a caring daughter. Soft diffused natural light. Neutral premium background: soft warm beige or pale indigo, softly blurred. Modern casual-premium attire, light colors. Photorealistic, shallow depth of field, portrait photography. No text, no logos, no watermarks, no illustration, no anime.'
    },
    {
      name: 'avatar-somchai',
      aspectRatio: '1:1',
      prompt:
        'Head-and-shoulders portrait photograph of a Thai man, early-to-mid 30s, with authentic Southeast Asian features — broad face, warm olive-brown skin, dark short hair, relaxed confident expression with a casual approachable smile — the look of an easygoing tech-savvy professional. Soft natural indoor light. Neutral premium background: soft off-white or warm sand, softly blurred. Modern casual-premium shirt, dark colors. Photorealistic, 35mm portrait lens bokeh. No text, no logos, no watermarks, no illustration, no anime.'
    },
    {
      name: 'avatar-hiroshi',
      aspectRatio: '1:1',
      prompt:
        'Head-and-shoulders portrait photograph of a Japanese man, mid-40s to early 50s, with authentic East Asian features — lean angular face, slightly greying short dark hair at temples, refined composed expression with a subtle thoughtful half-smile — the look of a design-appreciating professional, refined but not stiff. Soft directional natural light. Neutral premium background: muted deep indigo or warm off-white, softly blurred. Modern casual-premium attire, dark navy or charcoal. Photorealistic, 35mm portrait lens bokeh. No text, no logos, no watermarks, no illustration, no anime.'
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

async function generateAvatars() {
  await ensureDir(ROOT);
  console.log(`Generating ${PROMPTS.avatars.length} avatars → ${ROOT}/`);
  for (const item of PROMPTS.avatars) {
    const outPath = resolve(ROOT, `${item.name}.png`);
    process.stdout.write(`  • ${item.name} (1:1) ... `);
    try {
      const response = await ai.models.generateImages({
        model: 'imagen-4.0-generate-001',
        prompt: item.prompt,
        config: {
          numberOfImages: 1,
          aspectRatio: '1:1'
        }
      });
      const generated = response.generatedImages?.[0];
      if (!generated?.image?.imageBytes) throw new Error('no image bytes returned');
      const bytes = Buffer.from(generated.image.imageBytes, 'base64');
      await writeFile(outPath, bytes);
      console.log(`✓ ${(bytes.length / 1024).toFixed(0)}KB`);
    } catch (err) {
      console.error(`✗ ${(err as Error).message}`);
      process.exit(1);
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
else if (cmd === 'avatars') generateAvatars();
else if (cmd === 'video') generateVideo();
else {
  console.error('Usage: tsx scripts/generate-assets.ts <images|avatars|video>');
  process.exit(1);
}
