import Image from 'next/image';
import Link from 'next/link';
import HeroSlideshow from '@/components/HeroSlideshow';
import ScrollScene from '@/components/ScrollScene';
import { IconArrow } from '@/components/Icons';

/**
 * Act one. The camera moves through a frame.
 *
 * The scene is five layers stacked on a shared Z axis inside one perspective
 * container. Scroll progress (--p, published by ScrollScene) drives a single
 * dolly value, and each layer multiplies it by a different factor. Layers
 * nearer the camera move further, which is what reads as depth rather than as
 * a zoom.
 *
 *   depth  -900  photographic plate, furthest back
 *   depth  -520  the aperture
 *   depth  -260  inner rule
 *   depth     0  logo and headline
 *   depth   120  foreground vignette, passes the camera first
 *
 * TO SWAP IN A REAL RENDER: replace the .frame-aperture element with an <Image>
 * or a <video> of a Blender export. Keep the data-depth attribute and the
 * layer class; the transform maths does not care what is inside.
 */
export default function CinematicHero() {
  return (
    <ScrollScene height={260} label="Welcome" className="hero-scene">
      <div className="camera">
        {/* Layer 1: the photographic plate. Hero slides come from Supabase. */}
        <div className="layer" data-depth="-900">
          <div className="plate">
            <HeroSlideshow />
          </div>
        </div>

        {/* Layer 2: the frame the camera travels through. Replace with a render. */}
        <div className="layer" data-depth="-520">
          <div className="frame-aperture" aria-hidden="true" />
        </div>

        {/* Layer 3: a second frame just inside the first, for thickness. */}
        <div className="layer" data-depth="-260">
          <div className="frame-inner" aria-hidden="true" />
        </div>

        {/* Layer 4: the content plane. */}
        <div className="layer layer-content" data-depth="0">
          <div className="hero-copy">
            <Image
              src="/logo.png"
              alt="Amazing Church Philippines"
              width={720}
              height={288}
              priority
              className="hero-logo"
            />

            <p className="eyebrow">
              <span aria-hidden="true" className="eyebrow-rule" />
              <span className="gilt-text-bright">Welcome home</span>
              <span aria-hidden="true" className="eyebrow-rule" />
            </p>

            <h1 className="hero-title">
              There is a place for you here, and you are <em>already loved</em>
            </h1>

            <p className="hero-lede">
              Come exactly as you are. Bring your questions, your good weeks and your hard ones,
              and find a family that is glad you walked in.
            </p>

            <div className="hero-actions">
              <Link href="/signup" className="btn-primary group px-6 py-3 text-base">
                <span>Join the community</span>
                <IconArrow size={17} className="transition-transform duration-200 group-hover:translate-x-1" />
              </Link>
              <Link href="/live" className="btn-outline px-5 py-3 text-base">Watch live</Link>
            </div>
          </div>
        </div>

        {/* Layer 5: foreground falloff, sells the sense of passing through. */}
        <div className="layer" data-depth="120">
          <div className="foreground-vignette" aria-hidden="true" />
        </div>
      </div>

      <p className="scroll-cue" aria-hidden="true">
        <span>Scroll</span>
        <span className="scroll-cue-line" />
      </p>
    </ScrollScene>
  );
}
