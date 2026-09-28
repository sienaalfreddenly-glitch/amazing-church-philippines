'use client';
export default function ConfirmDeleteCourseButton({ id, name, back = '/courses' }) {
  return (
    <form action="/api/admin/courses/delete" method="post"
      onSubmit={e => {
        if (!confirm(`Delete ${name}? Its lessons and every enrollment and progress record in it are removed too. This cannot be undone.`)) e.preventDefault();
      }}>
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="back" value={back} />
      <button className="btn-danger text-xs">Delete</button>
    </form>
  );
}
