'use client';
import { useState } from 'react';

export default function SetTempPasswordButton({ id, name }) {
  const [open, setOpen] = useState(false);
  const [custom, setCustom] = useState('');
  const [result, setResult] = useState(null); // {password}
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState(false);

  async function submit() {
    setErr(''); setBusy(true);
    const res = await fetch('/api/admin/set-temp-password', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id, password: custom || undefined }),
    });
    setBusy(false);
    if (!res.ok) {
      const j = await res.json().catch(() => ({ error: 'Failed.' }));
      return setErr(j.error || 'Failed.');
    }
    const j = await res.json();
    setResult(j);
  }

  function copy() {
    navigator.clipboard.writeText(result.password);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }

  function close() {
    setOpen(false); setResult(null); setErr(''); setCustom(''); setCopied(false);
  }

  return (
    <>
      <button onClick={() => setOpen(true)}
        className="text-xs px-2.5 py-1 rounded-full border border-silver-light hover:border-brand hover:text-brand transition-colors">
        Temp password
      </button>

      {open && (
        <div className="fixed inset-0 z-50 bg-ink/40 backdrop-blur-sm flex items-center justify-center p-4" onClick={close}>
          <div className="card max-w-md w-full" onClick={e => e.stopPropagation()}>
            <div className="flex items-start justify-between">
              <div>
                <h3 className="text-lg">Set a temporary password</h3>
                <p className="text-sm text-ink/60">for <strong>{name}</strong></p>
              </div>
              <button onClick={close} className="text-2xl leading-none text-ink/50 hover:text-ink">×</button>
            </div>

            {!result ? (
              <div className="mt-4 space-y-3">
                <div>
                  <label className="label">Custom password (leave empty to auto-generate)</label>
                  <input className="input" type="text" placeholder="min 8 characters"
                    value={custom} onChange={e => setCustom(e.target.value)} />
                </div>
                <p className="text-xs text-ink/60">
                  The user will be forced to set a new password the moment they log in.
                </p>
                {err && <p className="text-sm text-red-700">{err}</p>}
                <div className="flex justify-end gap-2">
                  <button onClick={close} className="btn-outline">Cancel</button>
                  <button onClick={submit} disabled={busy} className="btn-primary">
                    {busy ? 'Setting…' : 'Set temporary password'}
                  </button>
                </div>
              </div>
            ) : (
              <div className="mt-4 space-y-3">
                <p className="text-sm">Send this to <strong>{name}</strong>:</p>
                <div className="rounded-xl bg-silver-light/60 p-3 flex items-center justify-between gap-2">
                  <code className="text-base font-mono select-all break-all">{result.password}</code>
                  <button onClick={copy} className="btn-outline text-xs">
                    {copied ? 'Copied!' : 'Copy'}
                  </button>
                </div>
                <p className="text-xs text-ink/60">
                  They'll be prompted to set a new password immediately after logging in.
                </p>
                <div className="flex justify-end">
                  <button onClick={close} className="btn-primary">Done</button>
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </>
  );
}
