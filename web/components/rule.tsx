// The masthead rule: a hairline broken by a centred label. Chronicle uses it to open a section
// the way a newspaper opens a column.
export function Rule({ label }: { label: string }) {
  return (
    <div className="flex items-center gap-5">
      <span className="h-px flex-1 bg-rule" />
      <span className="label whitespace-nowrap">{label}</span>
      <span className="h-px flex-1 bg-rule" />
    </div>
  );
}
