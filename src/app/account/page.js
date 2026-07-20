'use client';
import { useEffect, useState } from 'react';
import { createClient } from '@/lib/supabase-browser';
import { useRouter } from 'next/navigation';
import Avatar from '@/components/Avatar';

export default function Account() {
  const supabase = createClient();
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [msg, setMsg] = useState('');
  const [err, setErr] = useState('');
  const [profile, setProfile] = useState(null);
  const [fullName, setFullName] = useState('');
  const [contactNumber, setContactNumber] = useState('');
  const [leader, setLeader] = useState(null);
  const [latestLesson, setLatestLesson] = useState(null);

  useEffect(() => { (async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { router.push('/login'); return; }
    const { data, error } = await supabase.from('profiles').select('*').eq('id', user.id).single();
    if (error || !data) { setErr(error?.message || 'Profile not found. Run the updated schema in Supabase.'); setLoading(false); return; }
    setProfile(data);
    setFullName(data.full_name || '');
    setContactNumber(data.contact_number || '');
    if (data.leader_id) {
      const { data: ld } = await supabase.from('profiles')
        .select('full_name, email').eq('id', data.leader_id).single();
      setLeader(ld || null);
    }
    // Most recent verified lesson (RLS restricts to own completions automatically)
    const { data: lc } = await supabase
      .from('lesson_completions')
      .select('verified_at, lesson:course_lessons(title, ord, course:courses(code, name))')
      .order('verified_at', { ascending: false }).limit(1);
    if (lc && lc.length) setLatestLesson(lc[0]);
    setLoading(false);
  })(); }, []);

  async function uploadAvatar(e) {
    setErr(''); setMsg('');
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > 3 * 1024 * 1024) { setErr('Image must be under 3 MB.'); return; }
    setUploading(true);
    const ext = file.name.split('.').pop().toLowerCase();
    const path = `${profile.id}/avatar-${Date.now()}.${ext}`;
    const { error: upErr } = await supabase.storage.from('avatars').upload(path, file, {
      cacheControl: '3600', upsert: true, contentType: file.type,
    });
    if (upErr) { setUploading(false); setErr(upErr.message); return; }
    const { data: pub } = supabase.storage.from('avatars').getPublicUrl(path);
    const { error: saveErr } = await supabase.from('profiles')
      .update({ avatar_url: pub.publicUrl }).eq('id', profile.id);
    setUploading(false);
    if (saveErr) return setErr(saveErr.message);
    setProfile({ ...profile, avatar_url: pub.publicUrl });
    setMsg('Profile photo updated.');
    router.refresh();
  }

  async function save(e) {
    e.preventDefault(); setErr(''); setMsg(''); setSaving(true);
    const { error } = await supabase.from('profiles')
      .update({ full_name: fullName, contact_number: contactNumber || null })
      .eq('id', profile.id);
    setSaving(false);
    if (error) return setErr(error.message);
    setMsg('Saved.');
    router.refresh();
  }

  if (loading) return <p className="text-ink/60">Loading…</p>;
  if (!profile) return (
    <div className="max-w-lg mx-auto card mt-10">
      <h1 className="text-xl mb-2">Can't load your profile</h1>
      <p className="text-sm text-red-700">{err || 'Unknown error.'}</p>
      <p className="text-sm text-ink/60 mt-2">
        Make sure the latest <code>supabase/schema.sql</code> has been run in the Supabase SQL editor.
      </p>
    </div>
  );

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <h1 className="text-3xl">My account</h1>

      <div className="card flex items-center gap-5">
        <Avatar url={profile.avatar_url} name={profile.full_name} size={88} />
        <div className="flex-1">
          <p className="font-medium">{profile.full_name}</p>
          <p className="text-sm text-ink/60">{profile.email}</p>
          <label className="btn-outline mt-3 inline-flex cursor-pointer">
            {uploading ? 'Uploading…' : 'Change photo'}
            <input type="file" accept="image/*" className="hidden" onChange={uploadAvatar} disabled={uploading} />
          </label>
        </div>
      </div>

      <form onSubmit={save} className="card space-y-4">
        <h2 className="text-xl">Account information</h2>
        <div><label className="label">Full name</label>
          <input className="input" value={fullName} onChange={e=>setFullName(e.target.value)} required /></div>
        <div><label className="label">Contact number</label>
          <input className="input" placeholder="+63 9xx xxx xxxx"
            value={contactNumber} onChange={e=>setContactNumber(e.target.value)} /></div>
        <div><label className="label">Email</label>
          <input className="input bg-silver-light/50" value={profile.email} disabled /></div>
        {(profile.role === 'super_admin' || profile.role === 'admin') && (
          <div className="flex gap-3 items-baseline">
            <span className="label mb-0">Role</span>
            <span className="badge bg-silver-light">{profile.role.replace('_',' ')}</span>
            <span className="label mb-0 ml-4">Status</span>
            <span className={`badge ${profile.account_status==='approved' ? 'bg-brand-50 text-brand-700' : 'bg-silver-light'}`}>
              {profile.account_status}
            </span>
          </div>
        )}
        {leader && (
          <div><span className="label">Leader assigned</span>
            <p className="text-sm">{leader.full_name} <span className="text-ink/60">· {leader.email}</span></p>
          </div>
        )}
        <div>
          <span className="label">Most recent lesson finished</span>
          {latestLesson ? (
            <p className="text-sm">
              <span className="text-brand font-semibold">{latestLesson.lesson?.course?.code}</span>{' '}
              <span className="text-ink/70">· Lesson {latestLesson.lesson?.ord}</span>{' '}
              <span className="font-medium">{latestLesson.lesson?.title}</span>
              <span className="block text-xs text-ink/50 mt-0.5">
                Verified {new Date(latestLesson.verified_at).toLocaleDateString(undefined, { year:'numeric', month:'long', day:'numeric' })}
              </span>
            </p>
          ) : (
            <p className="text-sm text-ink/50">No lessons verified yet.</p>
          )}
        </div>
        {msg && <p className="text-sm text-brand">{msg}</p>}
        {err && <p className="text-sm text-red-700">{err}</p>}
        <button disabled={saving} className="btn-primary">{saving ? 'Saving…' : 'Save changes'}</button>
      </form>
    </div>
  );
}
