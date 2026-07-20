'use client';
export default function ConfirmDeleteUserButton({ id }) {
  return (
    <form action="/api/admin/delete-user" method="post"
      onSubmit={e => { if (!confirm('Delete this user permanently?')) e.preventDefault(); }}>
      <input type="hidden" name="id" value={id} />
      <button className="btn-danger text-xs px-2 py-1">Delete</button>
    </form>
  );
}
