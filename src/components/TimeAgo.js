'use client';
import { useEffect, useState } from 'react';
import { timeAgo } from '@/lib/format';

export default function TimeAgo({ date }) {
  const [label, setLabel] = useState(() => timeAgo(date));
  useEffect(() => {
    const id = setInterval(() => setLabel(timeAgo(date)), 30_000);
    return () => clearInterval(id);
  }, [date]);
  return <time dateTime={date} title={new Date(date).toLocaleString()}>{label}</time>;
}
