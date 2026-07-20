'use client';
import { useEffect, useRef } from 'react';

// Animated gradient orbs behind the hero + mouse-move parallax on the logo/title.
// Pure CSS transforms, no libraries.
export default function HeroParallax({ children }) {
  const wrap = useRef(null);
  const orb1 = useRef(null); const orb2 = useRef(null); const orb3 = useRef(null);

  useEffect(() => {
    let raf;
    function onMove(e) {
      const el = wrap.current; if (!el) return;
      const r = el.getBoundingClientRect();
      const x = ((e.clientX - r.left) / r.width - 0.5);   // -0.5..0.5
      const y = ((e.clientY - r.top) / r.height - 0.5);
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => {
        if (orb1.current) orb1.current.style.transform = `translate3d(${x * 40}px, ${y * 40}px, 0)`;
        if (orb2.current) orb2.current.style.transform = `translate3d(${x * -30}px, ${y * -30}px, 0)`;
        if (orb3.current) orb3.current.style.transform = `translate3d(${x * 20}px, ${y * -20}px, 0)`;
        el.style.setProperty('--tx', (x * 8).toFixed(2) + 'px');
        el.style.setProperty('--ty', (y * 8).toFixed(2) + 'px');
      });
    }
    const el = wrap.current;
    el?.addEventListener('mousemove', onMove);
    return () => { el?.removeEventListener('mousemove', onMove); cancelAnimationFrame(raf); };
  }, []);

  return (
    <div ref={wrap} className="relative overflow-hidden rounded-3xl">
      {/* Floating orbs */}
      <div ref={orb1} className="pointer-events-none absolute -top-24 -left-16 w-[420px] h-[420px] rounded-full opacity-70 blur-3xl transition-transform duration-500"
        style={{ background: 'radial-gradient(circle, rgba(177,85,100,0.55), transparent 70%)' }} />
      <div ref={orb2} className="pointer-events-none absolute -bottom-32 -right-20 w-[500px] h-[500px] rounded-full opacity-60 blur-3xl transition-transform duration-500"
        style={{ background: 'radial-gradient(circle, rgba(122,31,43,0.5), transparent 70%)' }} />
      <div ref={orb3} className="pointer-events-none absolute top-1/2 left-1/2 w-[300px] h-[300px] -translate-x-1/2 -translate-y-1/2 rounded-full opacity-40 blur-3xl transition-transform duration-500"
        style={{ background: 'radial-gradient(circle, rgba(255,235,220,0.7), transparent 70%)' }} />

      {/* Content moves subtly with the mouse via --tx/--ty vars */}
      <div className="relative" style={{ transform: 'translate3d(var(--tx,0), var(--ty,0), 0)', transition: 'transform 200ms ease-out' }}>
        {children}
      </div>
    </div>
  );
}
