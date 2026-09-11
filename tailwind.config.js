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
        ink: '#1A1614',
        paper: '#FBFAF7',
      },
      fontFamily: {
        sans: ['var(--font-sans)', 'system-ui', 'sans-serif'],
        display: ['var(--font-display)', 'Georgia', 'serif'],
      },
      boxShadow: {
        // Shadows carry the brand hue instead of neutral black.
        soft:  '0 1px 2px rgba(38,9,13,0.04), 0 6px 20px rgba(38,9,13,0.05)',
        lift:  '0 4px 10px rgba(38,9,13,0.06), 0 22px 45px rgba(122,31,43,0.10)',
        inset: 'inset 0 1px 0 rgba(255,255,255,0.55)',
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
