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
        silver: {
          DEFAULT: '#C9CACC',
          light:   '#EEEFF1',
          dark:    '#9A9CA0',
        },
        ink: '#141416',
        paper: '#FBFAF7',
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        display: ['Playfair Display', 'Georgia', 'serif'],
      },
      boxShadow: {
        soft: '0 2px 12px rgba(20,20,22,0.06)',
      },
    },
  },
  plugins: [],
};
