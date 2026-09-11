// Skeleton shaped like the page it stands in for: hero block, verse band,
// then the bento tiles. Beats a centred spinner, which tells the reader nothing
// about what is arriving.
export default function Loading() {
  return (
    <div className="space-y-16" aria-busy="true" aria-live="polite">
      <span className="sr-only">Loading</span>

      <div className="skeleton h-[380px] rounded-[28px]" />
      <div className="skeleton h-[220px] rounded-3xl" />

      <div className="grid auto-rows-[minmax(128px,auto)] grid-cols-1 gap-4 sm:grid-cols-4">
        <div className="skeleton rounded-2xl sm:col-span-2 sm:row-span-2 sm:min-h-[272px]" />
        <div className="skeleton h-32 rounded-2xl" />
        <div className="skeleton h-32 rounded-2xl" />
        <div className="skeleton h-32 rounded-2xl" />
      </div>
    </div>
  );
}
