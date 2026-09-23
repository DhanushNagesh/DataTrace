export function Section({
  title,
  note,
  children,
}: {
  title: string;
  note?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="border border-rule-soft border-t-[3px] border-t-rule bg-paper p-6">
      <h2 className="font-display text-2xl leading-tight">{title}</h2>
      {note && <p className="mt-2 max-w-3xl text-sm leading-relaxed text-ink-2">{note}</p>}
      <div className="mt-6">{children}</div>
    </section>
  );
}
