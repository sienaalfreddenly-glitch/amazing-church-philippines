// Minimal set of stroke-based icons (Lucide-style, hand-rolled).
// All accept size + className; stroke color inherits from parent via `currentColor`.

const base = {
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 1.75,
  strokeLinecap: 'round',
  strokeLinejoin: 'round',
};

function Svg({ size = 24, className = '', children }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" width={size} height={size}
      viewBox="0 0 24 24" className={className} {...base}>
      {children}
    </svg>
  );
}

// Two overlapping chat bubbles for Discussions
export const IconChat = (p) => (
  <Svg {...p}>
    <path d="M4 5h11a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-3l-4 3v-3H4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z" />
    <path d="M20 10h1a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-3v3l-4-3H9" />
  </Svg>
);

// Heart with a spark / share aura for Feed (testimonies + moments)
export const IconCamera = (p) => (
  <Svg {...p}>
    <path d="M12 20.5s-6-3.5-8-8a4.5 4.5 0 0 1 8-3 4.5 4.5 0 0 1 8 3c-2 4.5-8 8-8 8z" />
    <path d="M5 4l1.2 2M19 4l-1.2 2M12 2v1.5" />
  </Svg>
);
export const IconCalendar = (p) => (
  <Svg {...p}>
    <rect x="3" y="4" width="18" height="18" rx="2" />
    <path d="M16 2v4M8 2v4M3 10h18" />
  </Svg>
);
export const IconUsers = (p) => (
  <Svg {...p}>
    <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
    <circle cx="9" cy="7" r="4" />
    <path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75" />
  </Svg>
);
export const IconLive = (p) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="3" />
    <path d="M4.93 4.93a10 10 0 0 0 0 14.14M19.07 4.93a10 10 0 0 1 0 14.14M7.76 7.76a6 6 0 0 0 0 8.48M16.24 7.76a6 6 0 0 1 0 8.48" />
  </Svg>
);
export const IconHome = (p) => (
  <Svg {...p}>
    <path d="M3 9.5 12 3l9 6.5V21a1 1 0 0 1-1 1h-5v-7h-6v7H4a1 1 0 0 1-1-1z" />
  </Svg>
);
export const IconMapPin = (p) => (
  <Svg {...p}>
    <path d="M21 10c0 7-9 13-9 13S3 17 3 10a9 9 0 0 1 18 0z" />
    <circle cx="12" cy="10" r="3" />
  </Svg>
);
export const IconBook = (p) => (
  <Svg {...p}>
    <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20V2H6.5A2.5 2.5 0 0 0 4 4.5z" />
    <path d="M4 19.5V22h16" />
  </Svg>
);
export const IconGrad = (p) => (
  <Svg {...p}>
    <path d="M22 10 12 4 2 10l10 6 10-6z" />
    <path d="M6 12v5c3 3 9 3 12 0v-5M22 10v6" />
  </Svg>
);
export const IconVideo = (p) => (
  <Svg {...p}>
    <path d="m23 7-7 5 7 5V7z" />
    <rect x="1" y="5" width="15" height="14" rx="2" />
  </Svg>
);
export const IconInbox = (p) => (
  <Svg {...p}>
    <path d="M22 12h-6l-2 3h-4l-2-3H2M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z" />
  </Svg>
);
export const IconArrow = (p) => (
  <Svg {...p}>
    <path d="M5 12h14M13 5l7 7-7 7" />
  </Svg>
);
export const IconSparkle = (p) => (
  <Svg {...p}>
    <path d="M12 2 14.5 9.5 22 12l-7.5 2.5L12 22l-2.5-7.5L2 12l7.5-2.5z" />
  </Svg>
);

export const IconBell = (p) => (
  <Svg {...p}>
    <path d="M18 8a6 6 0 1 0-12 0c0 7-3 9-3 9h18s-3-2-3-9" />
    <path d="M13.7 21a2 2 0 0 1-3.4 0" />
  </Svg>
);

// A more literal camera lens icon (used in the composer)
export const IconPhoto = (p) => (
  <Svg {...p}>
    <rect x="2" y="6" width="20" height="14" rx="2" />
    <circle cx="12" cy="13" r="4" />
    <path d="M8 6 9.5 3.5h5L16 6" />
  </Svg>
);
