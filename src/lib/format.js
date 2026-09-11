const UNITS = [
  { limit: 60,               div: 1,        name: 'second' },
  { limit: 60 * 60,          div: 60,       name: 'minute' },
  { limit: 60 * 60 * 24,     div: 3600,     name: 'hour'   },
  { limit: 60 * 60 * 24 * 30, div: 86400,   name: 'day'    },
  { limit: 60 * 60 * 24 * 365, div: 2592000, name: 'month' },
  { limit: Infinity,         div: 31536000, name: 'year'   },
];

export function timeAgo(input) {
  if (!input) return '';
  const then = new Date(input).getTime();
  if (Number.isNaN(then)) return '';
  const secs = Math.max(1, Math.floor((Date.now() - then) / 1000));
  if (secs < 10) return 'just now';
  for (const u of UNITS) {
    if (secs < u.limit) {
      const n = Math.floor(secs / u.div);
      return `${n} ${u.name}${n === 1 ? '' : 's'} ago`;
    }
  }
  return new Date(input).toLocaleDateString();
}

const CHURCH_TZ = 'Asia/Manila';

/**
 * Event date/time pinned to Manila so the server render and the client
 * hydration agree regardless of the reader's own timezone.
 */
export function eventDate(input, opts = {}) {
  if (!input) return '';
  const d = new Date(input);
  if (Number.isNaN(d.getTime())) return '';
  return new Intl.DateTimeFormat('en-PH', {
    timeZone: CHURCH_TZ,
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    ...opts,
  }).format(d);
}

/** Day-number and month for compact date blocks, e.g. { day: '14', month: 'Sep' }. */
export function eventDateParts(input) {
  const d = new Date(input);
  if (Number.isNaN(d.getTime())) return { day: '', month: '' };
  const fmt = (options) => new Intl.DateTimeFormat('en-PH', { timeZone: CHURCH_TZ, ...options }).format(d);
  return { day: fmt({ day: 'numeric' }), month: fmt({ month: 'short' }) };
}
