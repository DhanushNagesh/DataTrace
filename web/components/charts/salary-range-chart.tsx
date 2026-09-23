import type { SalaryByRole } from "@/lib/api";
import { usd } from "@/lib/format";

// p25 to p75 as a ruled span with serifed ends and a solid median tick. All six numbers matter,
// so they are printed rather than hidden behind a tooltip; the span only makes them comparable.
export function SalaryRangeChart({ rows }: { rows: SalaryByRole[] }) {
  const min = Math.min(...rows.map((r) => r.p25));
  const max = Math.max(...rows.map((r) => r.p75));
  const span = max - min || 1;
  const at = (v: number) => ((v - min) / span) * 100;

  return (
    <div className="divide-y divide-rule-soft">
      {rows.map((row) => (
        <div
          key={row.role_family}
          className="grid grid-cols-[12rem_1fr_12rem] items-center gap-4 py-2.5"
        >
          <div className="label truncate text-ink-2">{row.role_family}</div>
          <div className="relative h-4">
            <div
              className="absolute top-1/2 h-px bg-ink"
              style={{ left: `${at(row.p25)}%`, width: `${at(row.p75) - at(row.p25)}%` }}
            />
            {[row.p25, row.p75].map((edge) => (
              <div
                key={edge}
                className="absolute top-1 h-2 w-px bg-ink"
                style={{ left: `${at(edge)}%` }}
              />
            ))}
            <div className="absolute top-0 h-4 w-[3px] bg-accent" style={{ left: `${at(row.median)}%` }} />
          </div>
          <div className="label text-right tabular-nums text-ink-3">
            {usd(row.p25)} <span className="text-ink">{usd(row.median)}</span> {usd(row.p75)}
            <span className="ml-2">n={row.n}</span>
          </div>
        </div>
      ))}
    </div>
  );
}
