/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // Rook accent purple (same values as the iOS Theme).
        primary: {
          DEFAULT: '#7C5CFA',
          light: '#9F86FF',
          dark: '#5B3FD6',
        },
        // Rook gunmetal surfaces.
        rook: {
          ink: '#0C0C12',
          canvas: '#111118',
          surface: '#1B1B23',
          elevated: '#26262F',
          line: 'rgba(255,255,255,0.08)',
          muted: '#9A9AA6',
          faint: '#5E5E69',
        },
        heat: '#FF7A45',
        mint: '#3EE6A8',
        gold: '#FFC94D',
        sky: '#5CC8FF',
      },
      fontFamily: {
        sans: ['"DM Sans"', 'system-ui', 'sans-serif'],
        display: ['Outfit', '"DM Sans"', 'system-ui', 'sans-serif'],
        mono: ['"DM Mono"', 'ui-monospace', 'monospace'],
      },
    },
  },
  plugins: [],
};
