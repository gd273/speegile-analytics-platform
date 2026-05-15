/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./src/**/*.{js,jsx,ts,tsx}"],
  safelist: [
    "translate-x-0",
    "-translate-x-full",
    "bg-opacity-50",
    "rotate-180",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
};
