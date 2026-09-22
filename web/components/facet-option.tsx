import Link from "next/link";

export function FacetOption({
  href,
  children,
  selected,
}: {
  href: string;
  children: React.ReactNode;
  selected: boolean;
}) {
  return (
    <Link
      href={href}
      className={`flex items-center justify-between gap-4 px-3 py-2 font-mono text-xs hover:bg-paper-2 ${
        selected ? "font-semibold text-ink" : "text-ink-2"
      }`}
    >
      <span>{children}</span>
      {selected && <span aria-hidden>×</span>}
    </Link>
  );
}
