import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { redirect } from 'next/navigation';
import { isAdmin } from '@/lib/roles';
import Link from 'next/link';

export const dynamic = 'force-dynamic';

const STATUS_STYLE = {
  completed: 'bg-brand-50 text-brand-700',
  enrolled:  'bg-amber-50 text-amber-700',
  dropped:   'bg-red-50 text-red-700',
};

export default async function CoursesPage() {
  const { user, profile } = await getSessionAndProfile();
  if (!user) redirect('/login');

  const supabase = createClient();
  const [{ data: courses }, { data: myEnroll }, { data: lessons }, { data: completions }] = await Promise.all([
    supabase.from('courses').select('id, code, name, description, prereq_id, is_active')
      .eq('is_active', true).order('code'),
    supabase.from('enrollments').select('id, course_id, status, completed_at, enrolled_at')
      .eq('user_id', user.id),
    supabase.from('course_lessons').select('id, course_id'),
    supabase.from('lesson_completions').select('lesson_id, enrollment_id'),
  ]);
  const codeById = new Map((courses || []).map(c => [c.id, c.code]));

  const lessonsByCourse = new Map();
  (lessons || []).forEach(l => {
    if (!lessonsByCourse.has(l.course_id)) lessonsByCourse.set(l.course_id, []);
    lessonsByCourse.get(l.course_id).push(l.id);
  });

  const enrollmentByCourse = new Map((myEnroll || []).map(e => [e.course_id, e]));
  const doneCountByEnrollment = new Map();
  (completions || []).forEach(c => {
    doneCountByEnrollment.set(c.enrollment_id, (doneCountByEnrollment.get(c.enrollment_id) || 0) + 1);
  });

  const completed = (myEnroll || []).filter(e => e.status === 'completed');
  const inProgress = (myEnroll || []).filter(e => e.status === 'enrolled');

  return (
    <div className="max-w-3xl mx-auto space-y-8">
      <div className="text-center">
        <h1 className="text-3xl">Courses</h1>
        <p className="text-ink/60 text-sm">Discipleship tracks and training programs.</p>
      </div>

      <div className="card"
        style={{ background: 'linear-gradient(135deg, rgba(122,31,43,0.06), rgba(177,85,100,0.03))' }}>
        <p className="text-xs uppercase tracking-wider text-brand font-semibold">Your progress</p>
        <div className="mt-3 grid sm:grid-cols-2 gap-4">
          <div>
            <p className="text-sm text-ink/60">Completed</p>
            <div className="mt-1 flex flex-wrap gap-1.5">
              {completed.length ? completed.map(e => {
                const c = courses?.find(c => c.id === e.course_id);
                return c && <span key={e.course_id} className="badge bg-brand-50 text-brand-700">{c.code}</span>;
              }) : <span className="text-sm text-ink/50">None yet</span>}
            </div>
          </div>
          <div>
            <p className="text-sm text-ink/60">Currently enrolled</p>
            <div className="mt-1 flex flex-wrap gap-1.5">
              {inProgress.length ? inProgress.map(e => {
                const c = courses?.find(c => c.id === e.course_id);
                return c && <span key={e.course_id} className="badge bg-amber-50 text-amber-700">{c.code}</span>;
              }) : <span className="text-sm text-ink/50">None</span>}
            </div>
          </div>
        </div>
        <p className="text-xs text-ink/50 mt-4">
          Enrollment is managed by admins. Ask your leader if you'd like to join a course.
        </p>
      </div>

      <section className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-xl">Available courses</h2>
          {isAdmin(profile?.role) &&
            <Link href="/admin/courses" className="btn-outline text-xs">Manage courses</Link>}
        </div>
        {courses?.length ? courses.map(c => {
          const me = enrollmentByCourse.get(c.id);
          const lessonIds = lessonsByCourse.get(c.id) || [];
          const doneCount = me ? (doneCountByEnrollment.get(me.id) || 0) : 0;
          const totalLessons = lessonIds.length;
          const pct = totalLessons ? Math.round((doneCount / totalLessons) * 100) : 0;
          return (
            <article key={c.id} className="card">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <h3 className="text-lg">{c.code} — {c.name}</h3>
                  {c.description && <p className="text-sm text-ink/70 mt-2 whitespace-pre-wrap">{c.description}</p>}
                  <div className="flex flex-wrap gap-2 mt-3">
                    <span className="badge bg-silver-light">{totalLessons} lesson{totalLessons === 1 ? '' : 's'}</span>
                    {c.prereq_id && <span className="badge bg-silver-light">Requires {codeById.get(c.prereq_id) || 'prereq'}</span>}
                  </div>
                </div>
                {me
                  ? <span className={`badge ${STATUS_STYLE[me.status]}`}>{me.status}</span>
                  : <span className="badge bg-silver-light text-ink/60">not enrolled</span>}
              </div>

              {me && totalLessons > 0 && (
                <div className="mt-4">
                  <div className="flex items-center justify-between text-xs mb-1">
                    <span className="text-ink/60">Progress</span>
                    <span className="font-semibold">{doneCount}/{totalLessons} verified · {pct}%</span>
                  </div>
                  <div className="h-2 rounded-full bg-silver-light overflow-hidden">
                    <div className="h-full bg-gradient-to-r from-brand to-brand-400 transition-all duration-500"
                      style={{ width: `${pct}%` }} />
                  </div>
                  <Link href={`/courses/${c.id}`} className="text-sm text-brand hover:underline mt-3 inline-block">
                    View lessons →
                  </Link>
                </div>
              )}
            </article>
          );
        }) : <p className="text-ink/60 text-center py-8">No courses available yet.</p>}
      </section>
    </div>
  );
}
