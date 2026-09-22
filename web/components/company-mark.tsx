import { companyDomain, monogram } from "@/lib/company";

// Always renders: the route falls back to a drawn monogram when the guessed domain has no icon,
// so there is no broken-image state to handle and this stays a server component with no JS.
export function CompanyMark({ name }: { name: string }) {
  const domain = companyDomain(name);
  const src = `/logo/${domain || "unknown"}?m=${encodeURIComponent(monogram(name))}`;

  return (
    <img
      src={src}
      alt=""
      width={40}
      height={40}
      loading="lazy"
      className="size-10 shrink-0 border border-rule-soft bg-paper object-contain p-1"
    />
  );
}
