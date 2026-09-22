// No source API gives us a company website, so the domain is guessed from the display name.
// It resolves for most single-word tech companies (Databricks, Cloudflare, Asana) and misses
// where the brand and the domain differ (Scale AI is scale.com). The logo route treats a miss
// as normal and draws a monogram, so a wrong guess costs nothing but a plain initial.
export function companyDomain(name: string): string {
  return name
    .toLowerCase()
    .replace(/[''’]/g, "")
    .replace(/\b(inc|llc|ltd|corp|corporation|co|company|group|holdings)\b/g, "")
    .replace(/[^a-z0-9]/g, "");
}

export function monogram(name: string): string {
  const words = name.split(/[\s-]+/).filter(Boolean);
  if (words.length >= 2) return (words[0][0] + words[1][0]).toUpperCase();
  return name.slice(0, 2).toUpperCase();
}
