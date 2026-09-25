import { cache } from 'react';
import { createClient } from '@/lib/supabase-server';
import { fallbackFor, CONTENT_BLOCKS } from '@/lib/content-slugs';

// Cache the whole table read for the lifetime of one request. Every page uses
// several blocks; hitting the database once and reading a map is cheaper than
// firing one query per call, and safer than trying to batch calls by hand.
const loadAll = cache(async () => {
  try {
    const supabase = createClient();
    const { data, error } = await supabase.from('site_content').select('slug, body');
    if (error || !data) return new Map();
    return new Map(data.map((r) => [r.slug, r.body ?? '']));
  } catch {
    // The table has not been created yet, or the network refused. Every caller
    // has a fallback, so a total read failure quietly ships the code defaults
    // rather than blanking every page on the site.
    return new Map();
  }
});

export async function getContent(slug, fallback) {
  const map = await loadAll();
  const stored = map.get(slug);
  if (stored && stored.trim() !== '') return stored;
  return fallback ?? fallbackFor(slug);
}

export async function getAllContent() {
  const map = await loadAll();
  return CONTENT_BLOCKS.map((b) => ({
    ...b,
    body: map.get(b.slug) ?? '',
    hasOverride: map.has(b.slug) && (map.get(b.slug) ?? '').trim() !== '',
  }));
}
