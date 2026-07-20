'use client';
import { useRef } from 'react';

// Wraps a native form and submits automatically when any <select> inside changes.
export default function AutoForm({ action, children, className = '' }) {
  const ref = useRef(null);
  return (
    <form ref={ref} action={action} method="post" className={className}
      onChange={() => ref.current?.submit()}>
      {children}
    </form>
  );
}
