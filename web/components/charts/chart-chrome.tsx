"use client";

import type { TooltipContentProps } from "recharts";

export const AXIS = {
  stroke: "var(--rule-soft)",
  tick: { fill: "var(--ink-3)", fontSize: 10, fontFamily: "var(--font-mono)" },
  tickLine: false,
};

export const GRID = { stroke: "var(--rule-soft)", strokeDasharray: "0", vertical: false } as const;

// The palette is one colour, so a second series is carried by texture and dash rather than by
// hue. That is the same channel a colour-vision-deficient or black-and-white reader falls back
// to anyway, and it is what the newsprint look wants.
export function Hatch() {
  return (
    <defs>
      <pattern id="hatch" width={6} height={6} patternTransform="rotate(45)" patternUnits="userSpaceOnUse">
        <rect width={6} height={6} fill="var(--paper)" />
        <line x1={0} y1={0} x2={0} y2={6} stroke="var(--ink)" strokeWidth={3} />
      </pattern>
    </defs>
  );
}

export function Tip({
  active,
  payload,
  label,
  unit = "",
}: Partial<TooltipContentProps<number, string>> & { unit?: string }) {
  if (!active || !payload?.length) return null;

  return (
    <div className="border border-rule bg-paper px-3 py-2 shadow-[3px_3px_0_0_var(--rule)]">
      <div className="label">{label}</div>
      {payload.map((entry) => (
        <div key={entry.name} className="mt-1 flex items-center gap-3 font-mono text-xs">
          <span className="text-ink-2">{entry.name}</span>
          <span className="ml-auto tabular-nums">
            {entry.value}
            {unit}
          </span>
        </div>
      ))}
    </div>
  );
}
