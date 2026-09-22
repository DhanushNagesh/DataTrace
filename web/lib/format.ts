export const count = (n: number) => n.toLocaleString("en-US");

export const usd = (n: number | null) =>
  n === null ? "—" : `$${Math.round(n / 1000)}k`;

export const pct = (n: number) => `${n}%`;

export const date = (iso: string) =>
  new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });

export const dateTime = (iso: string) =>
  new Date(iso).toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZoneName: "short",
  });

export const shortDay = (iso: string) =>
  new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric" });
