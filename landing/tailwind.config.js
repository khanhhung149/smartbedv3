/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class',
  content: ['./src/**/*.{html,js,svelte,ts}'],
  theme: {
    extend: {
      colors: {
        // SleepTech brand
        ink: '#0B0E1A',          // deep night blue (primary text on light, bg on dark)
        cloud: '#F7F8FA',        // off-white background
        moon: '#E6E9F2',         // surface tint
        primary: {
          DEFAULT: '#6366F1',    // indigo — sleep / dreams
          dark: '#4F46E5',
          soft: '#A5B4FC'
        },
        accent: '#F0ABFC',       // soft pink-violet for highlights
        sakura: '#FFB7C5'        // Japanese cherry-blossom accent for YumePad
      },
      fontFamily: {
        sans: ['"Inter Variable"', 'Inter', '"Noto Sans"', 'system-ui', 'sans-serif'],
        display: ['"Manrope"', '"Inter Variable"', 'system-ui', 'sans-serif'],
        jp: ['"Noto Sans JP"', '"Hiragino Sans"', 'system-ui', 'sans-serif']
      }
    }
  },
  plugins: [require('@tailwindcss/typography')]
};
