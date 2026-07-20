'use client';
export default function ConfirmDeleteEventButton({ id }) {
  return (
    <form action="/api/admin/events/delete" method="post"
      onSubmit={e => { if (!confirm('Delete this event?')) e.preventDefault(); }}>
      <input type="hidden" name="id" value={id} />
      <button className="btn-danger text-xs">Delete</button>
    </form>
  );
}
