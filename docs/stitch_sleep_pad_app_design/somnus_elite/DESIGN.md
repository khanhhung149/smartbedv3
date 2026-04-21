```markdown
# Design System Document: Visual Identity & Interface Guidelines

## 1. Overview & Creative North Star
**The Creative North Star: "The Nocturnal Laboratory"**

This design system moves away from the "utility-first" clutter of traditional health apps. We are building a "Nocturnal Laboratory"—an environment that feels scientifically rigorous yet profoundly restorative. This is an editorial approach to clinical data. 

To achieve this, we reject the standard rigid grid in favor of **Intentional Asymmetry** and **Tonal Depth**. The interface should feel like a high-end physical object—think of a matte-black medical instrument or a luxury watch face. We prioritize breathing room over density, using the generous `xl` and `lg` spacing tokens to allow data to "float" within a vast, calm void. By overlapping subtle glass layers and using high-contrast typography scales, we create a sense of effortless premium quality that guides the user into a state of rest.

---

## 2. Colors & Surface Philosophy

The color palette is rooted in the deep obsidian of the night, punctuated by "bio-luminescent" accents that signify life and health.

### Surface Hierarchy & The "No-Line" Rule
Standard UI relies on lines to separate ideas. This design system prohibits the use of 1px solid, high-contrast borders for sectioning. Boundaries are defined by **Background Color Shifts**.
- **Surface Layering:** Place a `surface_container_lowest` (#0a0e13) card on a `surface` (#101419) background to create deep, recessed "wells" for secondary data. 
- **Nesting:** Use the tier system to imply importance. A `surface_container_high` card sitting on a `surface_container` background creates an immediate visual "pop" for critical morning summaries.

### The "Glass & Gradient" Rule
To prevent the dark mode from feeling "flat" or "heavy," we utilize transparency.
- **Glassmorphism:** Floating elements (like navigation bars or quick-action sheets) must use `surface_container` with a 70% opacity and a `20px` to `40px` backdrop blur.
- **Signature Textures:** Main CTAs and Hero sections should not be flat. Apply a subtle linear gradient from `primary` (#a4fff8) to `primary_container` (#5ee7df) at a 135-degree angle. This adds "soul" and a soft glow reminiscent of a high-end medical monitor.

---

## 3. Typography: The Editorial Voice

We use **Inter** not as a functional font, but as a brand signifier. The contrast between massive `display-lg` numbers and tiny, precise `label-sm` metadata creates an authoritative, editorial feel.

*   **Data as Art:** Use `display-lg` for primary health metrics (e.g., Sleep Score or Heart Rate). The sheer size of the type conveys its importance, removing the need for loud colors or heavy icons.
*   **The Narrative Flow:** Headlines (`headline-md`) should be used sparingly to introduce "chapters" of the user’s health story. 
*   **Hierarchy through Tonality:** Always pair `text-primary` (#E6EDF3) for values and `text-secondary` (#8B96A5) for units or descriptors to maintain a clear visual map.

---

## 4. Elevation & Depth: Tonal Layering

Traditional drop shadows are forbidden. We achieve depth through **Ambient Light** and **Tonal Stacking**.

*   **The Layering Principle:** Depth is "stacked."
    *   *Level 0:* `surface` (The base "floor").
    *   *Level 1:* `surface_container_low` (Embedded data sections).
    *   *Level 2:* `surface_container_highest` (Floating cards and interactive elements).
*   **Ambient Shadows:** When a card needs to float (e.g., a modal), use a shadow with a `40px` blur, `0%` spread, and a color of `on_surface` at `6%` opacity. This mimics the soft dispersion of moonlight.
*   **The "Ghost Border":** If a container requires definition against a similar background, use the `outline_variant` token at **15% opacity**. This creates a "suggestion" of a border that feels premium rather than structural.

---

## 5. Components

### Cards & Lists
*   **The "No-Divider" Mandate:** Never use horizontal lines to separate list items. Use vertical white space (`1.5rem` to `2rem`) or alternate background tiers (`surface_container` vs `surface_container_low`) to define content blocks.
*   **Radius:** All containers must use the `DEFAULT` (20px) or `lg` (32px) corner radius to maintain the soft, organic "Sleep Pad" feel.

### Buttons
*   **Primary:** A gradient fill (`primary` to `primary_container`) with `on_primary_fixed` text. Shape: `full` (pill).
*   **Secondary:** No fill. A "Ghost Border" of `outline` at 20% opacity. 
*   **States:** On press, reduce the button scale to `0.98` rather than changing the color. This feels more tactile and mechanical.

### Health Chips
*   **Heart Rate:** Use `primary_container` (#5EE7DF) text on a 10% opacity version of the same color for the background.
*   **Respiration:** Use `secondary` (#B490F5) text on a 10% opacity background.
*   *Note:* Chips should always have a `full` corner radius to distinguish them from structural cards.

### Input Fields
*   Text inputs should be "Understated." Use a `surface_container_lowest` background with no border. The active state is indicated by a subtle 1px "Ghost Border" of `primary` at 40% opacity.

---

## 6. Do’s and Don’ts

### Do:
*   **Embrace the Void:** Use more negative space than you think is necessary. Space is a luxury.
*   **Use Asymmetry:** If you have three metrics, try making the most important one 2/3 width and the others 1/3, rather than a perfect 3-column grid.
*   **Layer Glass:** Use backdrop blurs for "Morning Summary" overlays to keep the user connected to their data.

### Don't:
*   **Don't use Pure Black:** Always use `background` (#101419) to ensure the "calm clinical" feel isn't too harsh.
*   **Don't use Standard Dividers:** If you feel the need for a line, increase your spacing instead.
*   **Don't use High-Contrast Shadows:** Shadows should be felt, not seen. If the shadow is clearly visible, it is too dark.
*   **Don't Over-Iconize:** Let the typography and the colors (`teal` for heart, `lavender` for breath) do the talking. Icons should be thin-stroke (1px) and used only when necessary.

---

*This design system is a living document. Every screen should feel like a page from a high-end wellness journal—quiet, authoritative, and deeply intentional.*```