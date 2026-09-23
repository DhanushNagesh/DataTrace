export type Search = Record<string, string | undefined>;

// Every facet is a link, so the whole filter state stays in the URL: shareable, cacheable by
// Vercel, and the page stays a server component with no client-side fetching.
export function withParams(current: Search, changes: Search): string {
  const next = new URLSearchParams();
  for (const [key, value] of Object.entries({ ...current, ...changes })) {
    if (value) next.set(key, value);
  }
  // Any filter change invalidates the page you were on
  if (Object.keys(changes).some((key) => key !== "offset")) next.delete("offset");
  return next.size ? `/postings?${next}` : "/postings";
}
