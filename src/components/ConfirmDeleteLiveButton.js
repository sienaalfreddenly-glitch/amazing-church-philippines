'use client';
export default function ConfirmDeleteLiveButton({ id }) {
  return (
    <form action="/api/admin/live-videos" method="post"
      onSubmit={e => { if (!confirm('Remove this video from the archive?')) e.preventDefault(); }}>
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="action" value="delete" />
      <button className="text-xs text-red-700 hover:underline">Delete</button>
    </form>
  );
}
