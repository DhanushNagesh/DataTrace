export function StatTile({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="border-l-[3px] border-l-accent bg-paper px-5 py-4">
      <div className="label text-ink-3">{label}</div>
      <div className="mt-2 font-display text-4xl leading-none">{value}</div>
      {hint && <div className="mt-2 text-sm text-ink-2">{hint}</div>}
    </div>
  );
}
