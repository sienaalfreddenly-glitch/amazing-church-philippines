'use client';
import { useEffect, useMemo, useRef, useState } from 'react';
import { createClient } from '@/lib/supabase-browser';
import Avatar from './Avatar';

// Extracts the @-token being typed at the caret (returns null if not typing one).
function currentToken(value, caret) {
  const before = value.slice(0, caret);
  const m = before.match(/@([A-Za-z0-9 ._'-]{0,40})$/);
  if (!m) return null;
  return { query: m[1], start: caret - m[0].length, end: caret };
}

export default function MentionInput({
  value, onChange, mentions, onMentionsChange,
  placeholder, className, minRows = 2, required, autoFocus,
}) {
  const supabase = useMemo(() => createClient(), []);
  const [candidates, setCandidates] = useState([]);
  const [open, setOpen] = useState(false);
  const [tok, setTok] = useState(null);       // {query,start,end}
  const [active, setActive] = useState(0);
  const ref = useRef(null);
  const rows = Math.max(minRows, value.split('\n').length);

  // Debounce a search when the token changes
  useEffect(() => {
    if (!tok) { setOpen(false); return; }
    const q = tok.query.trim();
    const t = setTimeout(async () => {
      let query = supabase.from('profiles')
        .select('id, full_name, avatar_url').eq('account_status', 'approved').limit(6);
      if (q) query = query.ilike('full_name', `%${q}%`);
      else query = query.order('full_name');
      const { data } = await query;
      setCandidates(data || []);
      setActive(0);
      setOpen(true);
    }, 120);
    return () => clearTimeout(t);
  }, [tok, supabase]);

  function handleChange(e) {
    const v = e.target.value;
    onChange(v);
    const t = currentToken(v, e.target.selectionStart || v.length);
    setTok(t);
    if (!t) setOpen(false);
  }

  function insert(p) {
    if (!tok) return;
    const before = value.slice(0, tok.start);
    const after = value.slice(tok.end);
    const insertText = `@${p.full_name} `;
    const next = before + insertText + after;
    onChange(next);
    // Track the mentioned user id (dedupe)
    if (!mentions.includes(p.id)) onMentionsChange([...mentions, p.id]);
    setOpen(false); setTok(null);
    // Move caret after inserted text
    requestAnimationFrame(() => {
      const pos = (before + insertText).length;
      ref.current?.setSelectionRange(pos, pos);
      ref.current?.focus();
    });
  }

  function handleKey(e) {
    if (!open || candidates.length === 0) return;
    if (e.key === 'ArrowDown') { e.preventDefault(); setActive((active + 1) % candidates.length); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); setActive((active - 1 + candidates.length) % candidates.length); }
    else if (e.key === 'Enter' || e.key === 'Tab') { e.preventDefault(); insert(candidates[active]); }
    else if (e.key === 'Escape') { setOpen(false); }
  }

  return (
    <div className="relative">
      <textarea ref={ref}
        className={className || 'input min-h-[100px] text-base'}
        placeholder={placeholder}
        rows={rows}
        value={value}
        onChange={handleChange}
        onKeyDown={handleKey}
        onBlur={() => setTimeout(() => setOpen(false), 150)}
        required={required}
        autoFocus={autoFocus}
      />
      {open && candidates.length > 0 && (
        <ul className="absolute z-30 left-2 mt-1 w-72 max-h-64 overflow-auto rounded-xl border border-silver-light bg-white shadow-lg">
          {candidates.map((p, i) => (
            <li key={p.id}>
              <button type="button" onMouseDown={e => { e.preventDefault(); insert(p); }}
                className={`w-full text-left flex items-center gap-2 px-3 py-2 hover:bg-silver-light/60
                  ${i === active ? 'bg-silver-light/70' : ''}`}>
                <Avatar url={p.avatar_url} name={p.full_name} size={28} />
                <span className="text-sm">{p.full_name}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

// Render body with @Name occurrences styled as brand-colored spans.
// Approximate — matches "@" followed by a first-last name pattern.
export function RenderMentions({ body }) {
  const parts = (body || '').split(/(@[A-Z][A-Za-z._'-]+(?:\s[A-Z][A-Za-z._'-]+){0,3})/g);
  return (
    <>
      {parts.map((p, i) =>
        p.startsWith('@')
          ? <span key={i} className="text-brand font-medium">{p}</span>
          : <span key={i}>{p}</span>
      )}
    </>
  );
}
