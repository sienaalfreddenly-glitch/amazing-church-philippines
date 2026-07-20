import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { redirect } from 'next/navigation';
import { isAdmin } from '@/lib/roles';
import AutoForm from '@/components/AutoForm';
import Link from 'next/link';

export const dynamic = 'force-dynamic';

export default async function ManageCourses() {
  const { profile } = await getSessionAndProfile();
  if (!profile || !isAdmin(profile.role)) redirect('/');

  const supabase = createClient();
  const [{ data: courses, error: coursesErr }, { data: members }, { data: enrollments }, { data: lessonCounts }] = await Promise.all([
    supabase.from('courses').select('id, code, name, description, prereq_id, is_active, created_at').order('code'),
    supabase.from('profiles')
      .select('id, full_name, email, avatar_url')
      .eq('account_status', 'approved').order('full_name'),
    supabase.from('enrollments')
      .select('*, course:courses(code, name), member:profiles!enrollments_user_id_fkey(full_name)')
      .order('enrolled_at', { ascending: false }),
    supabase.from('course_lessons').select('course_id'),
  ]);

  const courseList = courses || [];
  const codeById = new Map(courseList.map(c => [c.id, c.code]));
  const memberList = members || [];
  const enrollmentList = enrollments || [];
  const lessonCount = new Map();
  (lessonCounts || []).forEach(l => lessonCount.set(l.course_id, (lessonCount.get(l.course_id) || 0) + 1));

  return (
    <div className="space-y-10">
      <div>
        <h1 className="text-3xl">Courses</h1>
        <p className="text-ink/60 text-sm">Manage the course catalog, add lessons, and enroll members.</p>
        {coursesErr && <p className="text-sm text-red-700 mt-2">Could not load courses: {coursesErr.message}</p>}
      </div>

      {/* Add a new course */}
      <section className="space-y-4">
        <h2 className="text-xl">Catalog</h2>

        <details className="card">
          <summary className="cursor-pointer font-semibold text-brand">+ Add a new course</summary>
          <form action="/api/admin/courses/upsert" method="post"
            className="mt-4 grid sm:grid-cols-[8rem_1fr_1fr] gap-3 items-end">
            <div>
              <label className="label">Code</label>
              <input className="input" name="code" required placeholder="SOL 1" />
            </div>
            <div>
              <label className="label">Name</label>
              <input className="input" name="name" required placeholder="School of Leaders 1" />
            </div>
            <div>
              <label className="label">Prerequisite</label>
              <select className="input" name="prereq_id" defaultValue="">
                <option value="">— none —</option>
                {courseList.map(c => <option key={c.id} value={c.id}>{c.code}</option>)}
              </select>
            </div>
            <div className="sm:col-span-3">
              <label className="label">Description (optional)</label>
              <textarea className="input min-h-[70px]" name="description"
                placeholder="What this course covers, who it's for…" />
            </div>
            <div className="sm:col-span-3 flex justify-end">
              <button className="btn-primary">Add course</button>
            </div>
          </form>
        </details>

        <div className="card p-0 overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-[11px] uppercase tracking-wider text-ink/50 border-b border-silver-light">
                <th className="px-4 py-3">Code</th>
                <th className="px-4 py-3">Name</th>
                <th className="px-4 py-3">Prereq</th>
                <th className="px-4 py-3">Lessons</th>
                <th className="px-4 py-3">Active</th>
                <th className="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody>
              {courseList.length === 0 && (
                <tr><td colSpan="6" className="px-4 py-8 text-center text-ink/60">No courses yet.</td></tr>
              )}
              {courseList.map(c => (
                <tr key={c.id} className="border-t border-silver-light hover:bg-silver-light/25">
                  <td className="px-4 py-3 font-semibold">{c.code}</td>
                  <td className="px-4 py-3">{c.name}</td>
                  <td className="px-4 py-3">{c.prereq_id ? codeById.get(c.prereq_id) : <span className="text-ink/40">—</span>}</td>
                  <td className="px-4 py-3">{lessonCount.get(c.id) || 0}</td>
                  <td className="px-4 py-3">
                    <AutoForm action="/api/admin/courses/toggle">
                      <input type="hidden" name="id" value={c.id} />
                      <select name="is_active" defaultValue={c.is_active ? 'true' : 'false'}
                        className="input py-1 text-xs w-auto">
                        <option value="true">yes</option>
                        <option value="false">no</option>
                      </select>
                    </AutoForm>
                  </td>
                  <td className="px-4 py-3">
                    <Link href={`/admin/courses/${c.id}`} className="text-brand hover:underline text-xs font-semibold">
                      Manage lessons →
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      {/* Enrollment */}
      <section className="space-y-4">
        <h2 className="text-xl">Enroll a member</h2>
        <form action="/api/admin/courses/enroll" method="post"
          className="card grid sm:grid-cols-[1fr_1fr_auto] gap-3 items-end">
          <div>
            <label className="label">Member</label>
            <select className="input" name="user_id" required defaultValue="">
              <option value="" disabled>Select a member…</option>
              {memberList.map(m => (
                <option key={m.id} value={m.id}>{m.full_name} · {m.email}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="label">Course</label>
            <select className="input" name="course_id" required defaultValue="">
              <option value="" disabled>Select a course…</option>
              {courseList.filter(c => c.is_active).map(c => (
                <option key={c.id} value={c.id}>{c.code} — {c.name}</option>
              ))}
            </select>
          </div>
          <button className="btn-primary">Enroll</button>
          <p className="sm:col-span-3 text-xs text-ink/50">
            Prerequisites are checked automatically — if the member hasn't completed a required course, enrollment is blocked.
          </p>
        </form>

        <h3 className="text-sm font-semibold text-ink/70 uppercase tracking-wider">Active enrollments</h3>
        <div className="space-y-2">
          {enrollmentList.length === 0 && <p className="text-sm text-ink/60">Nobody enrolled yet.</p>}
          {enrollmentList.map(e => (
            <div key={e.id} className="card flex flex-wrap items-center justify-between gap-3">
              <div className="min-w-0">
                <p className="font-medium">
                  {e.member?.full_name} <span className="text-ink/60">·</span>{' '}
                  <span className="text-brand">{e.course?.code}</span> <span className="text-ink/60">{e.course?.name}</span>
                </p>
                <p className="text-xs text-ink/50">
                  Enrolled {new Date(e.enrolled_at).toLocaleDateString()}
                  {e.completed_at && ` · Completed ${new Date(e.completed_at).toLocaleDateString()}`}
                </p>
              </div>
              <div className="flex items-center gap-2">
                <AutoForm action="/api/admin/courses/status">
                  <input type="hidden" name="id" value={e.id} />
                  <select name="status" defaultValue={e.status}
                    className="input py-1 text-xs w-auto">
                    <option value="enrolled">enrolled</option>
                    <option value="completed">completed</option>
                    <option value="dropped">dropped</option>
                  </select>
                </AutoForm>
              </div>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
