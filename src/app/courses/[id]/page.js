import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { redirect, notFound } from 'next/navigation';
import Link from 'next/link';
import { IconMapPin } from '@/components/Icons';

export const dynamic = 'force-dynamic';

export default async function CourseDetail({ params }) {
  const { user } = await getSessionAndProfile();
  if (!user) redirect('/login');

  const supabase = createClient();
  const { data: course } = await supabase.from('courses')
    .select('id, code, name, description, prereq_id, is_active').eq('id', params.id).single();
  if (!course) notFound();

  const [{ data: lessons }, { data: enrollment }] = await Promise.all([
    supabase.from('course_lessons').select('*').eq('course_id', course.id).order('ord'),
    supabase.from('enrollments').select('*').eq('user_id', user.id).eq('course_id', course.id).maybeSingle(),
  ]);

  let doneIds = new Set();
  if (enrollment) {
    const { data: doneRows } = await supabase.from('lesson_completions')
      .select('lesson_id').eq('enrollment_id', enrollment.id);
    doneIds = new Set((doneRows || []).map(d => d.lesson_id));
  }

  const lessonList = lessons || [];
  const doneCount = lessonList.filter(l => doneIds.has(l.id)).length;
  const pct = lessonList.length ? Math.round((doneCount / lessonList.length) * 100) : 0;

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <div>
        <Link href="/courses" className="text-sm text-brand hover:underline">← All courses</Link>
        <h1 className="text-3xl mt-2">{course.code} — {course.name}</h1>
        {course.description && <p className="mt-2 text-ink/80 whitespace-pre-wrap">{course.description}</p>}
      </div>

      {enrollment && lessonList.length > 0 && (
        <div className="card"
          style={{ background: 'linear-gradient(135deg, rgba(122,31,43,0.06), rgba(177,85,100,0.03))' }}>
          <div className="flex items-center justify-between text-sm mb-2">
            <span className="text-ink/70">Your progress</span>
            <span className="font-semibold">{doneCount}/{lessonList.length} verified · {pct}%</span>
          </div>
          <div className="h-2 rounded-full bg-white/60 overflow-hidden">
            <div className="h-full bg-gradient-to-r from-brand to-brand-400 transition-all duration-500"
              style={{ width: `${pct}%` }} />
          </div>
        </div>
      )}

      {!enrollment && (
        <div className="card text-sm text-ink/70">
          You are not enrolled in this course yet. Please ask an admin to enroll you.
        </div>
      )}

      <div className="space-y-3">
        {lessonList.length === 0 && <p className="text-sm text-ink/60">Lessons will appear here once added.</p>}
        {lessonList.map(l => {
          const done = doneIds.has(l.id);
          return (
            <article key={l.id} className="card">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-xs uppercase tracking-wider text-brand font-semibold">Lesson {l.ord}</p>
                  <h3 className="text-lg mt-0.5">{l.title}</h3>
                  {l.description && <p className="text-sm text-ink/80 mt-2 whitespace-pre-wrap">{l.description}</p>}
                </div>
                <span className={`badge ${done ? 'bg-brand-50 text-brand-700' : 'bg-silver-light text-ink/60'}`}>
                  {done ? '✓ Verified' : 'Pending'}
                </span>
              </div>

              <div className="mt-3 grid sm:grid-cols-2 gap-2 text-sm">
                {l.meeting_at && (
                  <div><span className="label mb-0">Meeting</span> {new Date(l.meeting_at).toLocaleString()}</div>
                )}
                {l.meeting_location && (
                  <div className="inline-flex items-start gap-1"><IconMapPin size={14} className="mt-1 shrink-0" /> {l.meeting_location}</div>
                )}
                {l.meeting_url && (
                  <div className="sm:col-span-2"><a href={l.meeting_url} target="_blank" rel="noreferrer" className="text-brand hover:underline">Join meeting ↗</a></div>
                )}
                {l.slides_url && (
                  <div className="sm:col-span-2"><a href={l.slides_url} target="_blank" rel="noreferrer" className="text-brand hover:underline">Open slides ↗</a></div>
                )}
              </div>

              {l.assignment_title && (
                <div className="mt-3 rounded-xl border border-silver-light p-3 bg-silver-light/30">
                  <p className="text-xs uppercase tracking-wider text-brand font-semibold">Assignment</p>
                  <p className="font-semibold">{l.assignment_title}</p>
                  {l.assignment_body && <p className="text-sm mt-1 whitespace-pre-wrap">{l.assignment_body}</p>}
                  {l.assignment_due_at && <p className="text-xs text-ink/60 mt-1">Due {new Date(l.assignment_due_at).toLocaleString()}</p>}
                </div>
              )}

              {(l.todo_items || []).length > 0 && (
                <div className="mt-3">
                  <p className="text-xs uppercase tracking-wider text-ink/60 font-semibold mb-1">To-do</p>
                  <ul className="text-sm space-y-1">
                    {l.todo_items.map((t, i) => (
                      <li key={i} className="flex items-start gap-2">
                        <span className="mt-0.5 inline-block w-4 h-4 rounded border border-silver flex-shrink-0" />
                        <span>{t}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              <p className="text-xs text-ink/50 mt-4">Ask an admin to verify once you've completed this lesson.</p>
            </article>
          );
        })}
      </div>
    </div>
  );
}
