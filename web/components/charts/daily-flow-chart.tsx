"use client";

import { CartesianGrid, Legend, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import type { DailyFlow } from "@/lib/api";
import { shortDay } from "@/lib/format";
import { AXIS, GRID, Tip } from "./chart-chrome";

// The mart is one row per day per role family. Summing them is deliberate: thirteen families is
// far past what any palette can keep apart, and the role breakdown is what the mix sections show.
function byDay(rows: DailyFlow[]) {
  const days = new Map<string, { day: string; opened: number; closed: number }>();
  for (const row of rows) {
    const entry = days.get(row.day) ?? { day: row.day, opened: 0, closed: 0 };
    entry.opened += row.opened;
    entry.closed += row.closed;
    days.set(row.day, entry);
  }
  return [...days.values()]
    .sort((a, b) => a.day.localeCompare(b.day))
    .map((d) => ({ ...d, label: shortDay(d.day) }));
}

export function DailyFlowChart({ rows }: { rows: DailyFlow[] }) {
  const data = byDay(rows);

  return (
    <ResponsiveContainer width="100%" height={280}>
      <LineChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
        <CartesianGrid {...GRID} />
        <XAxis dataKey="label" minTickGap={28} {...AXIS} />
        <YAxis width={34} {...AXIS} />
        <Tooltip content={<Tip />} cursor={{ stroke: "var(--ink-3)", strokeWidth: 1 }} />
        <Legend verticalAlign="top" align="right" iconType="plainline" iconSize={16}
          wrapperStyle={{ fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: "0.14em",
            textTransform: "uppercase", color: "var(--ink-2)", paddingBottom: 10 }} />
        <Line isAnimationActive={false} name="Opened" dataKey="opened" stroke="var(--accent)"
          strokeWidth={2} dot={false} activeDot={{ r: 4, fill: "var(--accent)" }} />
        <Line isAnimationActive={false} name="Closed" dataKey="closed" stroke="var(--ink)"
          strokeWidth={2} strokeDasharray="5 4" dot={false} activeDot={{ r: 4, fill: "var(--ink)" }} />
      </LineChart>
    </ResponsiveContainer>
  );
}
