import Reveal from '@/components/Reveal';

/**
 * The opening of every interior page.
 *
 * Before this, each page started differently: some with a bare h1, some with a
 * heading and a stray paragraph, some with nothing at all. That is what made
 * the site feel like a set of pages rather than one place. This gives them all
 * the same eyebrow, title, lead, and gilt rule, in the same rhythm, so the
 * design reads as a system.
 *
 * eyebrow  a short label above the title, set in gilt
 * lead     one sentence saying what this page is for
 * scripture / reference  optional, for pages where it belongs
 * action   optional element on the right, usually a button
 */
export default function PageHeader({ eyebrow, title, lead, scripture, reference, action, children }) {
  return (
    <Reveal as="header" className="page-header">
      <div className="flex flex-wrap items-end justify-between gap-x-8 gap-y-4">
        <div className="min-w-0">
          {eyebrow && (
            <p className="gilt-text text-[11px] font-semibold uppercase tracking-[0.3em]">
              {eyebrow}
            </p>
          )}

          <h1 className={`text-4xl sm:text-5xl ${eyebrow ? 'mt-3' : ''}`}>{title}</h1>

          {lead && <p className="mt-4 max-w-prose text-ink/65">{lead}</p>}
        </div>

        {action && <div className="shrink-0">{action}</div>}
      </div>

      {scripture && (
        <blockquote className="mt-6 border-l-2 border-gilt/60 pl-4">
          <p className="max-w-prose font-display text-lg leading-snug text-ink/80">{scripture}</p>
          {reference && (
            <cite className="mt-1.5 block text-xs font-semibold not-italic tracking-wide text-brand">
              {reference}
            </cite>
          )}
        </blockquote>
      )}

      {children}

      <hr className="gilt-rule mt-6" />
    </Reveal>
  );
}
