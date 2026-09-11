'use client';
import { useRef } from 'react';

/**
 * Tracks the pointer and writes its position into --mx / --my, which the
 * .spotlight rule in globals.css uses to light the 1px border under the cursor.
 *
 * Writing CSS variables straight onto the node keeps this off the React render
 * path, so pointer movement never triggers a re-render.
 */
export default function Spotlight({ children, className = '' }) {
  const ref = useRef(null);

  function onMove(e) {
    const el = ref.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    el.style.setProperty('--mx', `${e.clientX - r.left}px`);
    el.style.setProperty('--my', `${e.clientY - r.top}px`);
  }

  return (
    <div ref={ref} onPointerMove={onMove} className={`spotlight ${className}`}>
      {children}
    </div>
  );
}
