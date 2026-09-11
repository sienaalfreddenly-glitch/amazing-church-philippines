'use client';
import { useEffect, useId, useRef } from 'react';

/**
 * The scroll engine.
 *
 * A scene is a tall track containing one sticky stage. As the track passes the
 * viewport the stage stays pinned, and this component publishes how far through
 * the track the reader is as a CSS variable, --p, from 0 to 1. Everything
 * cinematic on the page is CSS reading that one number, which keeps the
 * animation declarative and keeps JavaScript out of the per-frame path.
 *
 * Why not a library: pinning is what position:sticky already does natively, and
 * the progress value is four lines of arithmetic. GSAP with ScrollTrigger plus
 * Lenis would add roughly 70KB to a site whose readers are mostly on mid-range
 * phones, and smooth-scroll hijacking makes a page feel broken on those devices.
 *
 * Performance notes:
 *   - One passive scroll listener and one rAF per frame, shared by every scene.
 *   - Only scenes currently intersecting the viewport are measured, so an
 *     off-screen scene costs nothing.
 *   - The only thing written per frame is a custom property. CSS animates
 *     transform and opacity from it, both of which are composited.
 *
 * Tuning: `height` sets how much scrolling the scene consumes. 200 means the
 * stage stays pinned for two extra viewport heights. Lower is snappier.
 */

// One loop drives every scene on the page rather than one loop each.
// stage element -> its track element.
const scenes = new Map();
let frame = 0;
let queued = false;

function measure() {
  // Cleared before the work, so a scroll landing mid-measure still queues the
  // next frame rather than being swallowed.
  queued = false;
  for (const [el, track] of scenes) {
    const rect = track.getBoundingClientRect();
    // Progress runs 0 at the moment the track's top reaches the viewport top,
    // and 1 when its bottom is about to leave. Clamped so overscroll on iOS
    // cannot push it out of range.
    const distance = rect.height - window.innerHeight;
    const raw = distance > 0 ? -rect.top / distance : 0;
    const p = raw < 0 ? 0 : raw > 1 ? 1 : raw;
    el.style.setProperty('--p', p.toFixed(4));
  }
}

function schedule() {
  if (queued) return;
  queued = true;
  frame = requestAnimationFrame(measure);
}

// Cancelling a pending frame must also clear the flag. Leaving it set was a bug
// that wedged the whole engine: every later schedule() returned early and no
// scene ever updated again.
function stop() {
  cancelAnimationFrame(frame);
  queued = false;
}

export default function ScrollScene({
  children,
  height = 200,
  className = '',
  stageClassName = '',
  label,
}) {
  const trackRef = useRef(null);
  const stageRef = useRef(null);
  const id = useId();

  useEffect(() => {
    const track = trackRef.current;
    const stage = stageRef.current;
    if (!track || !stage) return;

    // Reduced motion: hold the scene at its resting state and never listen.
    if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) {
      stage.style.setProperty('--p', '1');
      stage.dataset.motion = 'off';
      return;
    }

    stage.dataset.motion = 'on';

    // Only pay for scenes that are actually on screen.
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          scenes.set(stage, track);
          schedule();
        } else {
          scenes.delete(stage);
        }
      },
      { rootMargin: '20% 0px' },
    );
    io.observe(track);

    window.addEventListener('scroll', schedule, { passive: true });
    window.addEventListener('resize', schedule, { passive: true });
    schedule();

    return () => {
      io.disconnect();
      scenes.delete(stage);
      window.removeEventListener('scroll', schedule);
      window.removeEventListener('resize', schedule);
      if (!scenes.size) stop();
    };
  }, []);

  return (
    <section
      ref={trackRef}
      aria-label={label}
      className={`scene-track ${className}`}
      style={{ '--scene-height': `${height}vh` }}
    >
      <div ref={stageRef} id={id} className={`scene-stage ${stageClassName}`}>
        {children}
      </div>
    </section>
  );
}
