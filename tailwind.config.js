/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        brand: {
          DEFAULT: '#7A1F2B',
          50:  '#FBF5F6',
          100: '#F3E1E4',
          200: '#E4B9C0',
          300: '#CE8791',
          400: '#B15564',
          500: '#7A1F2B',
          600: '#661923',
          700: '#4F131B',
          800: '#3A0E14',
          900: '#26090D',
        },
        // Warm neutral ramp — hue-matched to `paper` so grays never read blue.
        silver: {
          DEFAULT: '#C6C0BC',
          light:   '#EDE9E5',
          dark:    '#96908B',
        },
        // Antique brass, not yellow gold. Used as a material — hairlines, rules,
        // foil text — rather than as a second accent hue competing with brand.
        gilt: {
          DEFAULT: '#B08D57',
          light:   '#E3C99A',
          deep:    '#7A5C33',
        },
        ink: '#1A1614',
        paper: '#FBFAF7',
      },
      fontFamily: {
        sans: ['var(--font-sans)', 'system-ui', 'sans-serif'],
        display: ['var(--font-display)', 'Georgia', 'serif'],
      },
      boxShadow: {
        // Every tier stacks a contact shadow, a mid shadow and an ambient cast,
        // all tinted with the brand hue and all cast downward from a single
        // light source above the page. That stack is what reads as depth.
        soft: '0 1px 2px rgba(38,9,13,0.05), 0 4px 10px rgba(38,9,13,0.04), 0 12px 28px rgba(38,9,13,0.05)',
        lift: '0 2px 4px rgba(38,9,13,0.06), 0 10px 22px rgba(38,9,13,0.07), 0 28px 60px rgba(122,31,43,0.12)',
        deep: '0 4px 8px rgba(38,9,13,0.08), 0 18px 40px rgba(38,9,13,0.10), 0 48px 96px rgba(122,31,43,0.16)',
        gilt: '0 1px 0 rgba(227,201,154,0.35), 0 10px 30px rgba(122,92,51,0.18)',
        // Top highlight — the lit edge that makes a surface read as raised.
        rim: 'inset 0 1px 0 rgba(255,255,255,0.75), inset 0 -1px 0 rgba(38,9,13,0.05)',
      },
      zIndex: {
        base: '0',
        raised: '10',
        sticky: '30',
        overlay: '40',
        modal: '50',
      },
      maxWidth: {
        prose: '65ch',
      },
    },
  },
  plugins: [],
};
