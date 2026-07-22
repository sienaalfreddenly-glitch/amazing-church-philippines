'use client';
import { useEffect, useMemo, useState } from 'react';
import { createClient } from '@/lib/supabase-browser';

// Rotating background slideshow behind the "Welcome home" hero.
// Semi-transparent overlay keeps foreground (logo + text) readable.
export default function HeroSlideshow({ intervalMs = 5000 }) {
  const supabase = useMemo(() => createClient(), []);
  const [slides, setSlides] = useState([]);
  const [i, setI] = useState(0);

  useEffect(() => { (async () => {
    const { data } = await supabase.from('hero_slides')
      .select('image_url, caption').eq('is_active', true).order('ord');
    setSlides(data || []);
  })(); }, [supabase]);

  useEffect(() => {
    if (slides.length < 2) return;
    const t = setInterval(() => setI(p => (p + 1) % slides.length), intervalMs);
    return () => clearInterval(t);
  }, [slides.length, intervalMs]);

  if (slides.length === 0) return null;

  return (
    <div className="absolute inset-0 -z-0 overflow-hidden">
      {slides.map((s, idx) => (
        <div key={s.image_url + idx}
          className={`absolute inset-0 transition-opacity duration-1000 ease-in-out ${idx === i ? 'opacity-100' : 'opacity-0'}`}>
          <img src={s.image_url} alt={s.caption || ''}
            className="w-full h-full object-cover"
            style={{ opacity: 0.40 }} />
        </div>
      ))}
      {/* Soft radial + gradient wash — light around the center where the hero
          content sits so the logo & headline stay legible, letting the picture
          breathe elsewhere. */}
      <div className="absolute inset-0 pointer-events-none"
        style={{
          background:
            'radial-gradient(ellipse at center, rgba(251,250,247,0.75) 0%, rgba(251,250,247,0.35) 40%, rgba(251,250,247,0.15) 100%)',
        }} />
      <div className="absolute inset-0 pointer-events-none"
        style={{
          background:
            'linear-gradient(180deg, rgba(255,255,255,0.20) 0%, rgba(255,255,255,0) 30%, rgba(255,255,255,0) 70%, rgba(122,31,43,0.10) 100%)',
        }} />
    </div>
  );
}
