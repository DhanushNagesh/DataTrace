import { JetBrains_Mono, Playfair_Display, Source_Serif_4 } from "next/font/google";

// Three faces, three jobs: Playfair for headlines and posting titles, Source Serif for prose,
// JetBrains Mono for every label, number and control. next/font self-hosts them, so there is no
// render-blocking request to Google and no layout shift from a late swap.
export const display = Playfair_Display({
  subsets: ["latin"],
  variable: "--font-display",
  display: "swap",
});

export const body = Source_Serif_4({
  subsets: ["latin"],
  variable: "--font-body",
  display: "swap",
});

export const mono = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-mono",
  display: "swap",
});
