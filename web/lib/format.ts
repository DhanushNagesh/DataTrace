export const count = (n: number) => n.toLocaleString("en-US");

export const usd = (n: number | null) =>
  n === null ? "—" : `$${Math.round(n / 1000)}k`;

export const pct = (n: number) => `${n}%`;

// Pinned to the pipeline's own timezone. These pages render on Vercel, whose servers have no
// local time, so without this "updated at" came out in UTC while the schedule that produced it
// runs at 06:00 America/Los_Angeles.
export const dateTime = (iso: string) =>
  new Date(iso).toLocaleString("en-US", {
    timeZone: "America/Los_Angeles",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZoneName: "short",
  });

export const shortDay = (iso: string) =>
  new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric" });

// Hours up to a day, then whole days. Negative deltas (a board's clock running ahead of ours)
// fall through to "Just now" rather than rendering a negative age.
export const age = (iso: string) => {
  const hours = Math.floor((Date.now() - new Date(iso).getTime()) / 3_600_000);
  if (hours < 1) return "Just now";
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
};
