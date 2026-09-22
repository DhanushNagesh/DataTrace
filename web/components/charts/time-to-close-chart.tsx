"use client";

import { Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import type { TimeToClose } from "@/lib/api";
import { AXIS, GRID, Hatch, Tip } from "./chart-chrome";

// Two measures in the same unit (days), so one y axis and grouped bars. A second axis would let
// the two series be scaled independently and the comparison would mean nothing.
export function TimeToCloseChart({ rows }: { rows: TimeToClose[] }) {
  return (
    <ResponsiveContainer width="100%" height={320}>
      <BarChart data={rows} margin={{ top: 8, right: 8, bottom: 62, left: 0 }} barGap={2}>
        <Hatch />
        <CartesianGrid {...GRID} />
        <XAxis dataKey="role_family" angle={-35} textAnchor="end" interval={0} {...AXIS} />
        <YAxis width={34} {...AXIS} />
        <Tooltip content={<Tip unit="d" />} cursor={{ fill: "var(--rule-soft)", opacity: 0.5 }} />
        <Legend verticalAlign="top" align="right" iconType="square" iconSize={9}
          wrapperStyle={{ fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: "0.14em",
            textTransform: "uppercase", color: "var(--ink-2)", paddingBottom: 10 }} />
        <Bar isAnimationActive={false} name="Median days" dataKey="median_days" fill="var(--accent)" />
        <Bar isAnimationActive={false} name="90th percentile" dataKey="p90_days" fill="url(#hatch)"
          stroke="var(--ink)" strokeWidth={1} />
      </BarChart>
    </ResponsiveContainer>
  );
}
