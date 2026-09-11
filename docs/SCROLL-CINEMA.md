# Scroll cinema: how to customize

The homepage opens with a camera move through a cathedral arch. This explains
how it works and which numbers to change.

## What drives it

`src/components/ScrollScene.js` measures how far you have scrolled through a
scene and writes a single number, `--p`, onto that scene. It runs from 0 when
the scene arrives to 1 when it leaves.

Everything visual reads that number from CSS. JavaScript writes one value per
frame and never touches a style property directly, so the browser can composite
the whole scene on the GPU.

There is no animation library. Pinning is `position: sticky`, which browsers do
natively. GSAP with ScrollTrigger plus Lenis would have added around 70KB, and
smooth-scroll hijacking makes pages feel broken on mid-range Android phones,
which is what most of the congregation uses.

## The three files

| File | What it holds |
| --- | --- |
| `src/components/ScrollScene.js` | The scroll engine and the pinning wrapper |
| `src/components/CinematicHero.js` | The five layers of the hero scene |
| `src/app/cinema.css` | Every transform, and the footer |

## Changing the camera move

In `src/app/cinema.css`:

```css
.scene-stage {
  --dolly-range: 620px;   /* how far the camera travels, in px of Z */
}

.layer[data-depth='-900'] { --d: -900px; --s: 0.22; }
```

`--d` is where a layer starts on the Z axis. `--s` is how fast it closes on the
camera. Both matter. Distance alone is not parallax: if every layer shares one
speed, the planes travel together and the scene reads as a flat zoom rather than
as depth. Far layers want a low `--s`, near layers a high one.

To make the move longer or shorter, change the scene height in
`CinematicHero.js`:

```jsx
<ScrollScene height={260}>   {/* 260 means the stage pins for 2.6 viewports */}
```

Lower numbers feel snappier. Below about 150 the move gets abrupt.

## Changing colors, type, and spacing

Colors and fonts are not defined in `cinema.css`. They live in:

- `tailwind.config.js` — the `brand`, `gilt`, `ink`, and `paper` palettes, the
  shadow tiers, and the arch radius.
- `src/app/globals.css` — the CSS variables under `@layer base`, plus every
  button, card, and surface style.
- `src/app/layout.js` — the two typefaces, Outfit and Fraunces, loaded through
  `next/font`.

Change a brand color in `tailwind.config.js` and it propagates everywhere.

## Replacing the placeholder visuals

**The arch.** `.arch-aperture` in `cinema.css` is drawn with a border radius and
a very large box shadow that acts as the surrounding wall. To use a real render
from Blender or Framer, replace the `<div className="arch-aperture" />` in
`CinematicHero.js` with an `<Image>` or a `<video>`. Keep the `layer` class and
the `data-depth` attribute on the parent. The transform maths does not care what
is inside the layer.

**The background photograph.** It comes from the `hero_slides` table in
Supabase, managed at `/admin/hero-slides`. No code change needed.

**The logo.** `public/logo.png`. Note that the current file has an opaque light
rectangle baked in behind the word CHURCH, which shows against dark photos. A
transparent export would fix it.

## Mobile and accessibility

Both are handled in `cinema.css`, at the bottom of the hero section:

- Coarse pointers and screens under 640px get a shorter throw and a shallower
  layer stack. The narrative survives, the compositing costs less.
- `prefers-reduced-motion: reduce` unpins the scene entirely. The track
  collapses to its natural height, the decorative layers are hidden, and the
  content renders as an ordinary block. `ScrollScene` also skips attaching its
  listeners in that case, so nothing runs at all.

The scene is also safe with JavaScript disabled. `--p` defaults to 0 in CSS and
the stage renders its resting composition.

## Performance notes

- One scroll listener and one animation frame are shared by every scene, not one
  set each.
- A scene off screen is removed from the loop by an IntersectionObserver, so it
  costs nothing.
- Only `transform` and `opacity` are animated. Neither triggers layout.
- `will-change` is set on `.layer` only, which is the handful of elements that
  actually move.
