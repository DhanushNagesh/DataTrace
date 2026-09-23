import type { SeniorityMix } from "@/lib/api";

const SHORT: Record<string, string> = {
  Intern: "Int",
  Entry: "Ent",
  Mid: "Mid",
  Senior: "Sen",
  "Staff+": "Stf",
  "Director+": "Dir",
  Unspecified: "?",
};

// Small multiples instead of one stacked bar: seniority is ordered, and the x position carries
// that order, so the chart needs one hue and no legend. A stack would have to encode seven
// ordered levels in colour, and no seven-step ramp clears the contrast checks on both surfaces.
export function SeniorityMixChart({ rows, families }: { rows: SeniorityMix[]; families: string[] }) {
  const max = Math.max(...rows.map((r) => r.pct_of_family));

  return (
    <div className="grid gap-x-8 gap-y-6 sm:grid-cols-2 lg:grid-cols-3">
      {families.map((family) => {
        const levels = rows
          .filter((r) => r.role_family === family)
          .sort((a, b) => a.seniority_rank - b.seniority_rank);

        return (
          <figure key={family}>
            <figcaption className="label text-ink-2">{family}</figcaption>
            <div className="mt-3 flex h-24 items-end gap-[2px] border-b border-rule">
              {levels.map((level) => (
                <div
                  key={level.seniority}
                  className="group relative flex-1"
                  title={`${level.seniority}: ${level.pct_of_family}% (${level.postings})`}
                >
                  <div
                    className="w-full bg-accent"
                    style={{ height: `${Math.max((level.pct_of_family / max) * 96, 1)}px` }}
                  />
                </div>
              ))}
            </div>
            <div className="mt-1.5 flex gap-[2px] font-mono text-[10px] text-ink-3">
              {levels.map((level) => (
                <div key={level.seniority} className="flex-1 text-center">
                  {SHORT[level.seniority] ?? level.seniority}
                </div>
              ))}
            </div>
          </figure>
        );
      })}
    </div>
  );
}
