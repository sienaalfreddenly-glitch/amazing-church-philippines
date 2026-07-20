'use client';
import { useRef } from 'react';

// Wraps children in a container that tilts in 3D as the mouse moves over it.
// max = maximum tilt angle in degrees; scale bumps slightly on hover.
export default function Tilt3D({ children, max = 8, scale = 1.02, className = '' }) {
  const ref = useRef(null);
  const innerRef = useRef(null);

  function onMove(e) {
    const el = ref.current; if (!el) return;
    const r = el.getBoundingClientRect();
    const x = (e.clientX - r.left) / r.width;   // 0..1
    const y = (e.clientY - r.top) / r.height;
    const rx = ((0.5 - y) * 2) * max;   // rotate X
    const ry = ((x - 0.5) * 2) * max;   // rotate Y
    if (innerRef.current) {
      innerRef.current.style.transform =
        `perspective(900px) rotateX(${rx.toFixed(2)}deg) rotateY(${ry.toFixed(2)}deg) scale(${scale})`;
    }
  }
  function onLeave() {
    if (innerRef.current) innerRef.current.style.transform = '';
  }

  return (
    <div ref={ref} onMouseMove={onMove} onMouseLeave={onLeave}
      className={`[perspective:900px] ${className}`}>
      <div ref={innerRef} className="transition-transform duration-200 ease-out will-change-transform">
        {children}
      </div>
    </div>
  );
}
