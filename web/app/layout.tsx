import type { Metadata } from "next";
import Link from "next/link";
import { body, display, mono } from "@/lib/fonts";
import "./globals.css";

export const metadata: Metadata = {
  title: "DataTrace — every open role, counted",
  description:
    "US job postings pulled daily from Greenhouse, Lever, Ashby, SmartRecruiters, Rippling and RemoteOK, modelled in Postgres and served read-only.",
};

const NAV = [
  { href: "/postings", label: "Roles" },
  { href: "/intelligence", label: "Intelligence" },
];

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${display.variable} ${body.variable} ${mono.variable}`}>
      <body className="font-body antialiased">
        <header className="sticky top-0 z-40 border-b-[3px] border-rule bg-paper">
          <div className="mx-auto flex max-w-[1500px] flex-wrap items-center gap-x-8 gap-y-2 px-5 py-3">
            <Link href="/postings" className="font-display text-3xl leading-none tracking-tight">
              DataTrace
            </Link>
            <nav className="flex items-center gap-6">
              {NAV.map((item) => (
                <Link key={item.href} href={item.href} className="label text-ink-2 hover:text-ink">
                  {item.label}
                </Link>
              ))}
            </nav>
            <a
              href="https://github.com/dhanushnagesh"
              className="label ml-auto hidden bg-accent px-4 py-2 text-on-accent sm:block"
            >
              The pipeline
            </a>
          </div>
          <div className="mx-auto flex max-w-[1500px] items-center gap-4 px-5 pb-2">
            <span className="label text-ink-3">Job intelligence</span>
            <span className="h-px flex-1 bg-rule-soft" />
            <span className="label text-ink-3">Est. 2026</span>
          </div>
        </header>

        <main className="mx-auto max-w-[1500px] px-5 py-8">{children}</main>

        <footer className="mx-auto max-w-[1500px] border-t border-rule-soft px-5 py-8">
          <p className="label text-ink-3">Colophon</p>
          <p className="mt-2 max-w-3xl text-sm leading-relaxed text-ink-2">
            Public job board APIs only, US-accessible postings. Rebuilt every morning by a Step
            Functions pipeline: Lambda ingest → S3 → RDS Postgres → dbt → a read-only API behind
            API Gateway. No scraping, no recruiters, no ghost jobs.
          </p>
        </footer>
      </body>
    </html>
  );
}
