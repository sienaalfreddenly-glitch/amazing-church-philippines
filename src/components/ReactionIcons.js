// Clean, high-clarity SVG reaction badges. Bold silhouettes readable at 20px.

const palette = {
  love:   ['#F87171', '#DC2626'],
  pray:   ['#A78BFA', '#6D28D9'],
  amen:   ['#FBBF24', '#D97706'],
  bless:  ['#7DD3FC', '#0284C7'],
  praise: ['#FDE68A', '#CA8A04'],
};

const uid = () => 'g' + Math.random().toString(36).slice(2, 8);

function Badge({ id, size, from, to, children }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" width={size} height={size} viewBox="0 0 32 32"
      style={{ filter: 'drop-shadow(0 1px 1.5px rgba(0,0,0,0.15))' }}>
      <defs>
        <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={from} />
          <stop offset="100%" stopColor={to} />
        </linearGradient>
        <linearGradient id={id + 'h'} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="rgba(255,255,255,0.4)" />
          <stop offset="60%" stopColor="rgba(255,255,255,0)" />
        </linearGradient>
      </defs>
      <circle cx="16" cy="16" r="15" fill={`url(#${id})`} />
      <circle cx="16" cy="13" r="12" fill={`url(#${id}h)`} />
      <circle cx="16" cy="16" r="15" fill="none" stroke="rgba(0,0,0,0.15)" strokeWidth="0.6" />
      <g fill="#ffffff">{children}</g>
    </svg>
  );
}

// A classic heart, symmetric and full-bodied
export function LoveIcon({ size = 22 }) {
  const id = uid();
  return (
    <Badge id={id} size={size} from={palette.love[0]} to={palette.love[1]}>
      <path d="M16 25.5 C 7 20, 5.5 13, 10 10.5 C 13 9, 15 11, 16 13 C 17 11, 19 9, 22 10.5 C 26.5 13, 25 20, 16 25.5 Z" />
    </Badge>
  );
}

// Praying hands: two tall teardrops meeting at fingertips, joined at wrist
export function PrayIcon({ size = 22 }) {
  const id = uid();
  return (
    <Badge id={id} size={size} from={palette.pray[0]} to={palette.pray[1]}>
      {/* Left palm */}
      <path d="M14.6 6 C 13 8, 11.6 12, 11 17 C 10.7 19.3, 11.6 21.2, 13.2 22 L 15.5 22 L 15.5 6.5 C 15.5 6, 15 5.7, 14.6 6 Z" />
      {/* Right palm (mirror) */}
      <path d="M17.4 6 C 19 8, 20.4 12, 21 17 C 21.3 19.3, 20.4 21.2, 18.8 22 L 16.5 22 L 16.5 6.5 C 16.5 6, 17 5.7, 17.4 6 Z" />
      {/* Wrist band */}
      <rect x="11" y="21.6" width="10" height="2.6" rx="1.3" />
      {/* Cuff line */}
      <rect x="11" y="24.2" width="10" height="1.4" rx="0.7" opacity="0.6" />
    </Badge>
  );
}

// Latin cross — bold, centered, iconic
export function AmenIcon({ size = 22 }) {
  const id = uid();
  return (
    <Badge id={id} size={size} from={palette.amen[0]} to={palette.amen[1]}>
      <rect x="14" y="5" width="4" height="22" rx="0.7" />
      <rect x="8" y="11" width="16" height="4" rx="0.7" />
    </Badge>
  );
}

// Dove in flight — small body + head + two large arched wings
export function BlessIcon({ size = 22 }) {
  const id = uid();
  return (
    <Badge id={id} size={size} from={palette.bless[0]} to={palette.bless[1]}>
      {/* Left wing (up-arched) */}
      <path d="M15 16 C 12 10, 6 10, 3 14 C 6 15.5, 10 16.5, 15 16.5 Z" />
      {/* Right wing (up-arched) */}
      <path d="M17 16 C 20 10, 26 10, 29 14 C 26 15.5, 22 16.5, 17 16.5 Z" />
      {/* Body (teardrop pointing down) */}
      <path d="M13 15 C 13 13, 19 13, 19 15 L 18 22 C 17.8 23, 14.2 23, 14 22 Z" />
      {/* Head */}
      <circle cx="20.5" cy="13.2" r="2" />
      {/* Beak */}
      <path d="M22.4 12.9 L 24.5 12.7 L 22.4 14 Z" />
      {/* Eye */}
      <circle cx="21" cy="12.7" r="0.5" fill={palette.bless[1]} />
    </Badge>
  );
}

// Two hands raised with a bright sparkle above (praise / worship)
export function PraiseIcon({ size = 22 }) {
  const id = uid();
  return (
    <Badge id={id} size={size} from={palette.praise[0]} to={palette.praise[1]}>
      {/* Sparkle above */}
      <path d="M16 2 L 16.9 5.6 L 20.5 6.5 L 16.9 7.4 L 16 11 L 15.1 7.4 L 11.5 6.5 L 15.1 5.6 Z" />
      {/* Left raised hand: 4 fingers + palm */}
      <path d="M6.5 25 L 6.5 15.5 C 6.5 14, 8.3 14, 8.3 15.5 L 8.3 11 C 8.3 9.5, 10.1 9.5, 10.1 11 L 10.1 14.5 C 10.1 13, 11.9 13, 11.9 14.5 L 11.9 15 C 11.9 13.5, 13.7 13.5, 13.7 15 L 13.7 25 Z" />
      {/* Right raised hand (mirror) */}
      <path d="M25.5 25 L 25.5 15.5 C 25.5 14, 23.7 14, 23.7 15.5 L 23.7 11 C 23.7 9.5, 21.9 9.5, 21.9 11 L 21.9 14.5 C 21.9 13, 20.1 13, 20.1 14.5 L 20.1 15 C 20.1 13.5, 18.3 13.5, 18.3 15 L 18.3 25 Z" />
    </Badge>
  );
}

export const REACTION_ICONS = {
  love: LoveIcon,
  pray: PrayIcon,
  amen: AmenIcon,
  bless: BlessIcon,
  praise: PraiseIcon,
};
