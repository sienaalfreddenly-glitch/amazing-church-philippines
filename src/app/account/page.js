'use client';
import { useEffect, useState } from 'react';
import { createClient } from '@/lib/supabase-browser';
import { useRouter } from 'next/navigation';
import Avatar from '@/components/Avatar';
import SocialLinks from '@/components/SocialLinks';
import { roleLabel } from '@/lib/roles';
import NotificationMutes from '@/components/NotificationMutes';

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
  const [facebookUrl, setFacebookUrl] = useState('');
  const [instagramUrl, setInstagramUrl] = useState('');
  const [fieldErrors, setFieldErrors] = useState({});
  const [leader, setLeader] = useState(null);
  const [latestLesson, setLatestLesson] = useState(null);

  useEffect(() => { (async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { router.push('/login'); return; }
    const { data, error } = await supabase.from('profiles').select('id, full_name, email, role, account_status, avatar_url, leader_id, created_at, is_leader, must_change_password, facebook_url, instagram_url, title, terms_accepted_at, terms_accepted_version').eq('id', user.id).single();
    if (error || !data) { setErr(error?.message || 'Profile not found. Run the updated schema in Supabase.'); setLoading(false); return; }
    setProfile(data);
    setFullName(data.full_name || '');
    // contact_number is not readable through the profiles table any more.
    // This function returns it only to the member, their leader, or staff.
    const { data: myNumber } = await supabase.rpc('profile_contact', { target: user.id });
    setContactNumber(myNumber || '');
    setFacebookUrl(data.facebook_url || '');
    setInstagramUrl(data.instagram_url || '');
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
    // Store a path through our own media route rather than the absolute URL
    // Supabase returns. getPublicUrl builds that URL from whatever address this
    // browser was configured with, which on a dev machine is 127.0.0.1. Saved
    // literally, the photo then fails to load on every other device, because
    // 127.0.0.1 means whichever machine is doing the looking.
    const avatarPath = `/api/media/avatars/${path}`;
    const { error: saveErr } = await supabase.from('profiles')
      .update({ avatar_url: avatarPath }).eq('id', profile.id);
    setUploading(false);
    if (saveErr) return setErr(saveErr.message);
    setProfile({ ...profile, avatar_url: avatarPath });
    setMsg('Profile photo updated.');
    router.refresh();
  }

  // Members paste whatever is in their address bar, or just their handle.
  // Accept both and store one canonical https URL, which is what the database
  // constraint and the display component expect.
  function normalizeSocial(value, host) {
    const raw = value.trim().replace(/\/+$/, '');
    if (!raw) return { value: null };
    const handle = raw.replace(/^@/, '');
    if (/^[A-Za-z0-9._-]+$/.test(handle)) {
      return { value: `https://www.${host}/${handle}` };
    }
    let url;
    try {
      url = new URL(raw.startsWith('http') ? raw : `https://${raw}`);
    } catch {
      return { error: 'That does not look like a link or a username.' };
    }
    if (!url.hostname.endsWith(host)) {
      return { error: `That is not a ${host} link.` };
    }
    if (url.pathname === '/' || url.pathname === '') {
      return { error: 'Add your profile, not just the site.' };
    }
    return { value: `https://${url.hostname}${url.pathname}` };
  }

  async function save(e) {
    e.preventDefault(); setErr(''); setMsg('');

    const fb = normalizeSocial(facebookUrl, 'facebook.com');
    const ig = normalizeSocial(instagramUrl, 'instagram.com');
    const errors = {};
    if (fb.error) errors.facebook = fb.error;
    if (ig.error) errors.instagram = ig.error;
    setFieldErrors(errors);
    if (Object.keys(errors).length) return;

    setSaving(true);
    const { error } = await supabase.from('profiles')
      .update({
        full_name: fullName,
        contact_number: contactNumber || null,
        facebook_url: fb.value,
        instagram_url: ig.value,
      })
      .eq('id', profile.id);
    setSaving(false);
    if (error) return setErr(error.message);

    // Reflect the tidied-up values back into the form.
    setFacebookUrl(fb.value || '');
    setInstagramUrl(ig.value || '');
    setProfile({
      ...profile,
      contact_number: contactNumber || null,
      facebook_url: fb.value,
      instagram_url: ig.value,
    });
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
          <SocialLinks profile={{ ...profile, contact_number: contactNumber }} className="mt-2" />
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
          <input className="input nums" placeholder="+63 917 555 0142" inputMode="tel"
            value={contactNumber} onChange={e=>setContactNumber(e.target.value)} />
          <p className="mt-1.5 text-xs text-ink/45">
            Only you, your leader, and church staff can see this. Other members cannot.
          </p>
        </div>
        <div><label className="label">Email</label>
          <input className="input bg-silver-light/50" value={profile.email} disabled /></div>

        <fieldset className="space-y-4 border-t border-silver-light pt-4">
          <legend className="sr-only">Social links</legend>
          <p className="text-sm text-ink/60">
            Add your socials so other members can find you. Paste a link or just your username.
          </p>

          <div>
            <label className="label" htmlFor="facebook">Facebook</label>
            <input id="facebook" className={`input ${fieldErrors.facebook ? 'input-error' : ''}`}
              placeholder="facebook.com/yourname"
              aria-invalid={Boolean(fieldErrors.facebook)}
              aria-describedby={fieldErrors.facebook ? 'facebook-error' : undefined}
              value={facebookUrl} onChange={e=>setFacebookUrl(e.target.value)} />
            {fieldErrors.facebook && <p id="facebook-error" className="field-error">{fieldErrors.facebook}</p>}
          </div>

          <div>
            <label className="label" htmlFor="instagram">Instagram</label>
            <input id="instagram" className={`input ${fieldErrors.instagram ? 'input-error' : ''}`}
              placeholder="@yourname"
              aria-invalid={Boolean(fieldErrors.instagram)}
              aria-describedby={fieldErrors.instagram ? 'instagram-error' : undefined}
              value={instagramUrl} onChange={e=>setInstagramUrl(e.target.value)} />
            {fieldErrors.instagram && <p id="instagram-error" className="field-error">{fieldErrors.instagram}</p>}
          </div>
        </fieldset>
        {(profile.role === 'super_admin' || profile.role === 'admin') && (
          <div className="flex gap-3 items-baseline">
            <span className="label mb-0">Role</span>
            <span className="badge bg-silver-light">{roleLabel(profile.role)}</span>
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

      <section className="card">
        <h2 className="text-xl">Notifications</h2>
        <div className="mt-3">
          <NotificationMutes myId={profile.id} />
        </div>
      </section>
    </div>
  );
}
