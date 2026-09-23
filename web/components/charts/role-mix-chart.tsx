import type { RoleMix } from "@/lib/api";
import { count } from "@/lib/format";

// One series, so no legend and no palette: bar length is the whole message and every value is
// printed, which is why this ships no JavaScript and needs no hover layer.
export function RoleMixChart({ rows }: { rows: RoleMix[] }) {
  const max = Math.max(...rows.map((r) => r.postings));

  return (
    <div className="divide-y divide-rule-soft">
      {rows.map((row) => (
        <div
          key={row.role_family}
          className="grid grid-cols-[12rem_1fr_7rem] items-center gap-4 py-1.5"
        >
          <div className="label truncate text-ink-2">{row.role_family}</div>
          <div className="h-3 bg-paper-2">
            <div className="h-3 bg-accent" style={{ width: `${(row.postings / max) * 100}%` }} />
          </div>
          <div className="label text-right tabular-nums text-ink-2">
            {count(row.postings)}
            <span className="ml-2 text-ink-3">{row.pct_of_all}%</span>
          </div>
        </div>
      ))}
    </div>
  );
}
