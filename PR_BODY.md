# Redesign site visuals: typography, surfaces, layout, missing states

## What changed

A design pass over the public site. No framework or dependency changes, and no functional changes to auth, posting, or admin.

**Typography.** Swapped Inter and Playfair for Outfit and Fraunces, loaded through `next/font`. The previous `@import` sat after the `@tailwind` directives, which is invalid CSS ordering, so the font request was being dropped entirely. Added 500 and 600 weights, a 65-character prose measure, balanced heading wrap, and tabular figures for dates and counts.

**Color and surface.** Warmed the `silver` ramp so neutrals share a hue with `paper` instead of reading blue against it. Shadows now carry the brand red rather than neutral black. Removed the 135-degree gradient from primary buttons. The daily verse band is rebuilt from off-centre radial stops with a grain overlay, and its quote glyph moved out of the text flow, where it had been inflating the first line box and opening a gap beneath it.

**Layout.** The four equal feature cards are now an asymmetric bento. Discussions anchors a 2x2 tile, Feed and Events sit beside it, and Leaders spans the remaining two columns horizontally. Cards lost their border and carry hierarchy through elevation alone. Card CTAs pin to the floor so button rows line up across variable content. `Tilt3D` gained a `fill` prop for full-height grid cells.

**Navigation.** Replaced the horizontally scrolling link strip, which hid destinations off the right edge with no affordance that they existed, with inline links carrying an active-page underline plus a mobile disclosure panel that closes on Escape and on navigate.

**Previously missing.** Added a 404 page, an error boundary, a homepage-shaped skeleton loading state, a skip-to-content link, a site-wide focus ring, a reduced-motion block, Open Graph and Twitter metadata, and privacy and terms pages so the footer links resolve.

**Correctness.** Event dates are pinned to Asia/Manila through new formatters, so the server render and client hydration agree regardless of the reader's timezone.

## Verification

Production build compiles clean, 49 pages generated. Checked in the browser at desktop width and at 375px, including the mobile menu, the empty events state, and the 404 page.

## Before merging

- The privacy and terms copy is a first draft written from what the app actually does. It needs a read from church leadership, including confirmation of the Supabase and Facebook hosting claims.
- `metadataBase` is set to the Vercel domain. Update it if a custom domain is planned, or social preview images will resolve to the wrong host.

## Unrelated, noticed in passing

`public/logo.png` has an opaque light rectangle baked in behind the word CHURCH. It is visible against hero photos and on the current live site. Worth a transparent-background re-export, but out of scope here.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
