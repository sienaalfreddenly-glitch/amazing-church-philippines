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
