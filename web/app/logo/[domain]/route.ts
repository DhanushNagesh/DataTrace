import { NextResponse } from "next/server";

// Icons are proxied rather than hotlinked: the visitor's browser only ever talks to this site,
// so browsing the board doesn't hand a third party a list of the companies you looked at.
// Vercel caches each one for a week, so the upstream sees one request per company per week.
const UPSTREAM = "https://icons.duckduckgo.com/ip3";
const WEEK = 604_800;

// Next requires a literal here, so it can't reference WEEK
export const revalidate = 604800;

function monogramSvg(letters: string) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
  <rect width="64" height="64" fill="#f2ebdc"/>
  <text x="32" y="33" font-family="Georgia, serif" font-size="26" fill="#17150f"
        text-anchor="middle" dominant-baseline="central">${letters}</text>
</svg>`;
}

export async function GET(
  request: Request,
  { params }: { params: Promise<{ domain: string }> },
) {
  const { domain } = await params;
  const letters = (new URL(request.url).searchParams.get("m") ?? "?")
    .slice(0, 2)
    .replace(/[^A-Za-z0-9]/g, "");

  // The domain is a guess, so a 404 is the expected case, not an error
  const icon = /^[a-z0-9]{1,40}$/.test(domain)
    ? await fetch(`${UPSTREAM}/${domain}.com.ico`, { next: { revalidate: WEEK } }).catch(() => null)
    : null;

  if (icon?.ok) {
    return new NextResponse(await icon.arrayBuffer(), {
      headers: {
        "content-type": icon.headers.get("content-type") ?? "image/x-icon",
        "cache-control": `public, max-age=${WEEK}, immutable`,
      },
    });
  }

  return new NextResponse(monogramSvg(letters || "?"), {
    headers: {
      "content-type": "image/svg+xml",
      "cache-control": `public, max-age=${WEEK}, immutable`,
    },
  });
}
