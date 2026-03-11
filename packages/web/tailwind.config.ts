import type { Config } from "tailwindcss";

const config: Config = {
  darkMode: ["class"],
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
    "./lib/**/*.{ts,tsx}",
    "./styles/**/*.{css}",
  ],
  theme: {
    extend: {
      colors: {
        background: "hsl(var(--background))",
        foreground: "hsl(var(--foreground))",
        muted: "hsl(var(--muted))",
        card: "hsl(var(--card))",
        primary: "hsl(var(--primary))",
        accent: "hsl(var(--accent))",
      },
      boxShadow: {
        glass: "0 20px 40px rgba(0, 0, 0, 0.1)",
      },
      borderRadius: {
        lg: "1rem",
      },
      backgroundImage: {
        "hero-glow":
          "radial-gradient(circle at 20% 20%, rgba(255, 166, 58, 0.25) 0, rgba(255, 166, 58, 0) 45%), radial-gradient(circle at 80% 30%, rgba(64, 132, 255, 0.25) 0, rgba(64, 132, 255, 0) 40%)",
      },
    },
  },
  plugins: [],
};

export default config;
