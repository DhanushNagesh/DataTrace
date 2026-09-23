import { CompanyMark } from "@/components/company-mark";
import type { Posting } from "@/lib/api";
import { age, usd } from "@/lib/format";

const NEW_DAYS = 7;

function isNew(iso: string) {
  return Date.now() - new Date(iso).getTime() < NEW_DAYS * 86_400_000;
}

// Fall back to first_seen_at for a board that publishes no date at all
const postedAt = (posting: Posting) => posting.published_at ?? posting.first_seen_at;

export function JobCard({ posting }: { posting: Posting }) {
  return (
    <article className="flex flex-col border border-rule-soft border-l-[3px] border-l-accent bg-paper p-4">
      <div className="flex gap-3">
        <CompanyMark name={posting.company_name} />
        <div className="min-w-0">
          <h3 className="font-display text-[19px] leading-snug">
            <a href={posting.url} target="_blank" rel="noopener noreferrer" className="hover:underline">
              {posting.title}
            </a>
          </h3>
          {/* Rippling repeats every office in one location string; two lines is the cap before a
              card with four offices pushes the whole row's height. */}
          <p className="label mt-1 line-clamp-2 text-ink-3">
            {posting.company_name}
            <span> · {posting.location ?? posting.work_mode}</span>
          </p>
        </div>
      </div>

      <div className="mt-3 flex flex-wrap items-center gap-x-2 gap-y-1.5">
        {isNew(postedAt(posting)) && (
          <span className="label bg-accent px-2 py-1 text-on-accent">New</span>
        )}
        <span className="label border border-rule px-1.5 py-1">{posting.seniority}</span>
        {posting.salary_annual_mid_usd && (
          <span className="label text-ink-2">{usd(posting.salary_annual_mid_usd)}</span>
        )}
        <span className="label text-ink-3">{posting.role_family}</span>
      </div>

      <div className="mt-auto flex items-center justify-between gap-3 border-t border-rule-soft pt-3">
        <span className="label text-ink-3">
          {posting.source} · {age(postedAt(posting))}
        </span>
        <a
          href={posting.url}
          target="_blank"
          rel="noopener noreferrer"
          className="label text-accent hover:underline"
        >
          Apply →
        </a>
      </div>
    </article>
  );
}
