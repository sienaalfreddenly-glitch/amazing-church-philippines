import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { redirect, notFound } from 'next/navigation';
import { isAdmin } from '@/lib/roles';
import Avatar from '@/components/Avatar';
import Link from 'next/link';

export const dynamic = 'force-dynamic';

export default async function CourseAdmin({ params }) {
  const { profile } = await getSessionAndProfile();
  if (!profile || !isAdmin(profile.role)) redirect('/');

  const supabase = createClient();
  const { data: course } = await supabase.from('courses')
    .select('id, code, name, description, prereq_id, is_active').eq('id', params.id).single();
  if (!course) notFound();
  let prereqCode = null;
  if (course.prereq_id) {
    const { data: p } = await supabase.from('courses').select('code').eq('id', course.prereq_id).single();
    prereqCode = p?.code || null;
  }

  const [{ data: lessons }, { data: enrollments }, { data: completions }] = await Promise.all([
    supabase.from('course_lessons').select('*').eq('course_id', course.id).order('ord'),
    supabase.from('enrollments')
      .select('id, user_id, status, member:profiles!enrollments_user_id_fkey(full_name, avatar_url, email)')
      .eq('course_id', course.id).order('enrolled_at'),
    supabase.from('lesson_completions').select('*'),
  ]);

  const lessonList = lessons || [];
  const enrollList = enrollments || [];
  const doneSet = new Set((completions || []).map(c => `${c.enrollment_id}:${c.lesson_id}`));

  return (
    <div className="space-y-10">
      <div>
        <Link href="/admin/courses" className="text-sm text-brand hover:underline">← All courses</Link>
        <h1 className="text-3xl mt-2">{course.code} — {course.name}</h1>
        {prereqCode && <p className="text-sm text-ink/60">Requires {prereqCode}</p>}
        {course.description && <p className="mt-2 text-ink/80 whitespace-pre-wrap">{course.description}</p>}
      </div>

      {/* Add a lesson */}
      <section className="space-y-4">
        <h2 className="text-xl">Lessons ({lessonList.length})</h2>

        <details className="card">
          <summary className="cursor-pointer font-semibold text-brand">+ Add a new lesson</summary>
          <LessonForm course_id={course.id} nextOrd={(lessonList[lessonList.length-1]?.ord || 0) + 1} />
        </details>

        <div className="space-y-4">
          {lessonList.length === 0 && <p className="text-sm text-ink/60">No lessons yet — add the first one above.</p>}
          {lessonList.map(l => {
            return (
              <details key={l.id} className="card">
                <summary className="cursor-pointer flex items-center justify-between gap-3">
                  <div className="min-w-0">
                    <p className="text-xs uppercase tracking-wider text-brand font-semibold">Lesson {l.ord}</p>
                    <p className="font-semibold">{l.title}</p>
                  </div>
                  <span className="text-xs text-ink/50">click to expand</span>
                </summary>

                <div className="mt-4 space-y-4 border-t border-silver-light pt-4">
                  {l.description && <p className="text-sm whitespace-pre-wrap">{l.description}</p>}
                  <div className="grid sm:grid-cols-2 gap-3 text-sm">
                    {l.meeting_at && <div><span className="label mb-0">Meeting</span> {new Date(l.meeting_at).toLocaleString()}</div>}
                    {l.meeting_location && <div><span className="label mb-0">Location</span> {l.meeting_location}</div>}
                    {l.meeting_url && <div className="sm:col-span-2"><a href={l.meeting_url} target="_blank" rel="noreferrer" className="text-brand hover:underline">Join link ↗</a></div>}
                    {l.slides_url && <div className="sm:col-span-2"><a href={l.slides_url} target="_blank" rel="noreferrer" className="text-brand hover:underline">Slides ↗</a></div>}
                  </div>
                  {l.assignment_title && (
                    <div className="rounded-xl border border-silver-light p-3 bg-silver-light/30">
                      <p className="text-xs uppercase tracking-wider text-brand font-semibold">Assignment</p>
                      <p className="font-semibold">{l.assignment_title}</p>
                      {l.assignment_body && <p className="text-sm mt-1 whitespace-pre-wrap">{l.assignment_body}</p>}
                      {l.assignment_due_at && <p className="text-xs text-ink/60 mt-1">Due {new Date(l.assignment_due_at).toLocaleString()}</p>}
                    </div>
                  )}
                  {(l.todo_items || []).length > 0 && (
                    <div>
                      <p className="text-xs uppercase tracking-wider text-ink/60 font-semibold mb-1">To-do</p>
                      <ul className="text-sm list-disc pl-5">
                        {l.todo_items.map((t, i) => <li key={i}>{t}</li>)}
                      </ul>
                    </div>
                  )}

                  {/* Member verification grid */}
                  {enrollList.length > 0 && (
                    <div>
                      <p className="text-xs uppercase tracking-wider text-ink/60 font-semibold mb-2">Verify completion</p>
                      <div className="grid sm:grid-cols-2 gap-2">
                        {enrollList.map(e => {
                          const done = doneSet.has(`${e.id}:${l.id}`);
                          return (
                            <form key={e.id} action="/api/admin/lessons/verify" method="post"
                              className="flex items-center justify-between gap-2 rounded-lg border border-silver-light px-3 py-2">
                              <div className="flex items-center gap-2 min-w-0">
                                <Avatar url={e.member?.avatar_url} name={e.member?.full_name || ''} size={28} />
                                <span className="text-sm truncate">{e.member?.full_name}</span>
                              </div>
                              <input type="hidden" name="enrollment_id" value={e.id} />
                              <input type="hidden" name="lesson_id" value={l.id} />
                              <input type="hidden" name="course_id" value={course.id} />
                              <input type="hidden" name="verified" value={done ? 'false' : 'true'} />
                              <button className={`text-xs px-2.5 py-1 rounded-full transition
                                ${done
                                  ? 'bg-brand text-white'
                                  : 'border border-silver-light hover:border-brand hover:text-brand'}`}>
                                {done ? '✓ Verified' : 'Mark done'}
                              </button>
                            </form>
                          );
                        })}
                      </div>
                    </div>
                  )}

                  <div className="pt-4 border-t border-silver-light flex flex-wrap gap-3 items-start">
                    <details className="flex-1">
                      <summary className="cursor-pointer text-sm text-brand font-semibold">Edit this lesson</summary>
                      <LessonForm course_id={course.id} lesson={l} nextOrd={l.ord} />
                    </details>
                    <form action="/api/admin/lessons/delete" method="post">
                      <input type="hidden" name="id" value={l.id} />
                      <input type="hidden" name="course_id" value={course.id} />
                      <button className="btn-danger text-xs">Delete lesson</button>
                    </form>
                  </div>
                </div>
              </details>
            );
          })}
        </div>
      </section>
    </div>
  );
}

function LessonForm({ course_id, lesson, nextOrd }) {
  const l = lesson || {};
  const todoStr = (l.todo_items || []).join('\n');
  const dt = (v) => v ? new Date(v).toISOString().slice(0, 16) : '';
  return (
    <form action="/api/admin/lessons/upsert" method="post" className="mt-3 space-y-3">
      <input type="hidden" name="course_id" value={course_id} />
      {l.id && <input type="hidden" name="id" value={l.id} />}
      <div className="grid sm:grid-cols-[6rem_1fr] gap-3">
        <div>
          <label className="label">Order</label>
          <input className="input" name="ord" type="number" min="1" defaultValue={l.ord || nextOrd} required />
        </div>
        <div>
          <label className="label">Title</label>
          <input className="input" name="title" defaultValue={l.title || ''} required placeholder="Lesson title" />
        </div>
      </div>
      <div>
        <label className="label">Description (optional)</label>
        <textarea className="input min-h-[80px]" name="description" defaultValue={l.description || ''} placeholder="What this lesson covers" />
      </div>
      <div className="grid sm:grid-cols-3 gap-3">
        <div>
          <label className="label">Meeting time</label>
          <input className="input" name="meeting_at" type="datetime-local" defaultValue={dt(l.meeting_at)} />
        </div>
        <div>
          <label className="label">Meeting location</label>
          <input className="input" name="meeting_location" defaultValue={l.meeting_location || ''} placeholder="Zoom / room / church address" />
        </div>
        <div>
          <label className="label">Meeting link</label>
          <input className="input" name="meeting_url" defaultValue={l.meeting_url || ''} placeholder="https://…" />
        </div>
      </div>
      <div>
        <label className="label">Slides URL</label>
        <input className="input" name="slides_url" defaultValue={l.slides_url || ''} placeholder="Google Slides / PDF / PowerPoint link" />
      </div>
      <div className="rounded-xl border border-silver-light p-3 space-y-3">
        <p className="text-xs uppercase tracking-wider text-brand font-semibold">Assignment (optional)</p>
        <input className="input" name="assignment_title" defaultValue={l.assignment_title || ''} placeholder="Assignment title" />
        <textarea className="input min-h-[70px]" name="assignment_body" defaultValue={l.assignment_body || ''} placeholder="Details" />
        <div>
          <label className="label">Due</label>
          <input className="input" name="assignment_due_at" type="datetime-local" defaultValue={dt(l.assignment_due_at)} />
        </div>
      </div>
      <div>
        <label className="label">To-do checklist (one item per line)</label>
        <textarea className="input min-h-[90px]" name="todo_items" defaultValue={todoStr}
          placeholder={"Read John 3\nWatch intro video\nSubmit reflection"} />
      </div>
      <div className="flex justify-end">
        <button className="btn-primary">{l.id ? 'Save changes' : 'Add lesson'}</button>
      </div>
    </form>
  );
}
