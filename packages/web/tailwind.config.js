/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  // Rook is dark-only (matches the iOS app): <html class="dark"> in index.html.
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        // Rook accent purple (same values as the iOS Theme).
        primary: {
          DEFAULT: '#7C5CFA',
          light: '#9F86FF',
          dark: '#5B3FD6',
        },
        // Rook gunmetal surfaces; dark-mode grays map onto them so the whole app matches iOS.
        rook: {
          canvas: '#111118',
          surface: '#1B1B23',
          elevated: '#26262F',
          muted: '#9A9AA6',
          faint: '#5E5E69',
        },
        gray: {
          700: '#26262F',
          800: '#1B1B23',
          900: '#111118',
        },
        accent: {
          orange: '#F97316',
          green: '#22C55E',
        },
        surface: {
          DEFAULT: '#FFFFFF',
          secondary: '#F8F7FF',
          dark: '#0F0F1A',
        },
      },
      fontFamily: {
        sans: ['DM Sans', 'system-ui', 'sans-serif'],
        mono: ['DM Mono', 'monospace'],
      },
    },
  },
  plugins: [],
};
