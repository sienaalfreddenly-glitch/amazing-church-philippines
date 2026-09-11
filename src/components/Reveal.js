'use client';
import { useEffect, useRef, useState } from 'react';

/**
 * Reveals its children once they cross into the viewport, rather than on mount,
 * so sections below the fold animate when the reader arrives at them instead of
 * having already played off screen.
 *
 * Fails open. The content is visible by default and is only hidden once this
 * effect has armed it, so a reader with JavaScript disabled, a hydration
 * failure, or a stalled observer still sees the page. Anything already on
 * screen at mount is shown without waiting for a callback, which also covers
 * browsers that restore a scroll position on reload.
 *
 * delay staggers siblings. as lets the wrapper be a semantic element rather
 * than adding another div to the tree.
 */
export default function Reveal({ children, delay = 0, as: Tag = 'div', className = '', ...rest }) {
  const ref = useRef(null);
  const [armed, setArmed] = useState(false);
  const [shown, setShown] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const reduced = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    if (reduced || typeof IntersectionObserver === 'undefined') {
      setShown(true);
      return;
    }

    // Already on screen: show it now rather than waiting on a callback.
    const box = el.getBoundingClientRect();
    if (box.top < window.innerHeight && box.bottom > 0) {
      setArmed(true);
      setShown(true);
      return;
    }

    setArmed(true);

    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setShown(true);
          io.disconnect();
        }
      },
      { rootMargin: '0px 0px -12% 0px', threshold: 0.08 },
    );

    io.observe(el);
    return () => io.disconnect();
  }, []);

  return (
    <Tag
      ref={ref}
      data-armed={armed}
      data-shown={shown}
      style={{ '--reveal-delay': `${delay}ms` }}
      className={`reveal ${className}`}
      {...rest}
    >
      {children}
    </Tag>
  );
}
