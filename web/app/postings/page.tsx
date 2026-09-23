import Link from "next/link";
import { Facet } from "@/components/facet";
import { FacetOption } from "@/components/facet-option";
import { JobCard } from "@/components/job-card";
import { Rule } from "@/components/rule";
import { getPostings, getRoleMix, getStats } from "@/lib/api";
import { count, dateTime } from "@/lib/format";
import { withParams, type Search } from "@/lib/query";

const SENIORITIES = ["Intern", "Entry", "Mid", "Senior", "Staff+", "Director+", "Unspecified"];
const WORK_MODES = ["Remote (anywhere)", "Remote (US)", "On-site / hybrid"];
const SOURCES = ["greenhouse", "lever", "ashby", "smartrecruiters", "rippling", "remoteok"];
const MIN_SALARY = ["80000", "120000", "160000", "200000"];
const SORTS: Record<string, string> = {
  newest: "Newest first",
  oldest: "Oldest first",
  salary_high: "Pay: high to low",
  salary_low: "Pay: low to high",
  company: "Company A–Z",
};

const PAGE_SIZE = 24;

export default async function Postings({ searchParams }: { searchParams: Promise<Search> }) {
  const params = await searchParams;
  const offset = Number(params.offset ?? 0) || 0;

  const [page, roleMix, stats] = await Promise.all([
    getPostings({ ...params, limit: PAGE_SIZE, offset }),
    getRoleMix(),
    getStats(),
  ]);

  const filters = { ...params, offset: undefined };
  const anyFilter = Object.entries(filters).some(([key, value]) => value && key !== "sort");
  const lastPage = offset + PAGE_SIZE >= page.total;

  return (
    <div className="space-y-6">
      <Rule label="Open roles" />

      {/* A plain GET form for the free-text fields; the facets below are links. Between them the
          page never fetches from the browser and every view has its own URL. */}
      <form className="border border-rule">
        <div className="flex flex-col divide-y divide-rule-soft sm:flex-row sm:divide-x sm:divide-y-0">
          <label className="flex flex-1 flex-col gap-1 px-4 py-3">
            <span className="label text-ink-3">Title or company</span>
            <input
              name="q"
              defaultValue={params.q ?? ""}
              maxLength={100}
              placeholder="analytics engineer"
              className="bg-transparent font-display text-xl outline-none placeholder:text-ink-3"
            />
          </label>
          <label className="flex flex-1 flex-col gap-1 px-4 py-3 sm:max-w-xs">
            <span className="label text-ink-3">Company</span>
            <input
              name="company"
              defaultValue={params.company ?? ""}
              maxLength={100}
              placeholder="stripe"
              className="bg-transparent font-display text-xl outline-none placeholder:text-ink-3"
            />
          </label>
          {(["role_family", "seniority", "work_mode", "source", "min_salary", "sort"] as const).map(
            (key) =>
              params[key] ? <input key={key} type="hidden" name={key} value={params[key]} /> : null,
          )}
          <button type="submit" className="label bg-accent px-8 py-3 text-on-accent sm:px-10">
            Search
          </button>
        </div>
      </form>

      <div className="flex flex-wrap items-center gap-2">
        <Facet label="Role family" value={params.role_family}>
          {roleMix.map((row) => (
            <FacetOption
              key={row.role_family}
              href={withParams(filters, {
                role_family: params.role_family === row.role_family ? undefined : row.role_family,
              })}
              selected={params.role_family === row.role_family}
            >
              {row.role_family} ({count(row.postings)})
            </FacetOption>
          ))}
        </Facet>

        <Facet label="Level" value={params.seniority}>
          {SENIORITIES.map((level) => (
            <FacetOption
              key={level}
              href={withParams(filters, {
                seniority: params.seniority === level ? undefined : level,
              })}
              selected={params.seniority === level}
            >
              {level}
            </FacetOption>
          ))}
        </Facet>

        <Facet label="Work mode" value={params.work_mode}>
          {WORK_MODES.map((mode) => (
            <FacetOption
              key={mode}
              href={withParams(filters, {
                work_mode: params.work_mode === mode ? undefined : mode,
              })}
              selected={params.work_mode === mode}
            >
              {mode}
            </FacetOption>
          ))}
        </Facet>

        <Facet label="Pay at least" value={params.min_salary && `$${Number(params.min_salary) / 1000}k+`}>
          {MIN_SALARY.map((floor) => (
            <FacetOption
              key={floor}
              href={withParams(filters, {
                min_salary: params.min_salary === floor ? undefined : floor,
              })}
              selected={params.min_salary === floor}
            >
              ${Number(floor) / 1000}k or more
            </FacetOption>
          ))}
        </Facet>

        <Facet label="Board" value={params.source}>
          {SOURCES.map((source) => (
            <FacetOption
              key={source}
              href={withParams(filters, { source: params.source === source ? undefined : source })}
              selected={params.source === source}
            >
              {source}
            </FacetOption>
          ))}
        </Facet>

        <Facet label="Sort" value={params.sort && SORTS[params.sort]}>
          {Object.entries(SORTS).map(([key, label]) => (
            <FacetOption
              key={key}
              href={withParams(filters, { sort: key === "newest" ? undefined : key })}
              selected={(params.sort ?? "newest") === key}
            >
              {label}
            </FacetOption>
          ))}
        </Facet>

        {anyFilter && (
          <Link href="/postings" className="label px-3 py-2 text-ink-3 underline hover:text-ink">
            Clear filters
          </Link>
        )}
      </div>

      <div className="flex flex-wrap items-baseline justify-between gap-3 border-y border-rule py-3">
        <p className="font-display text-2xl">
          {count(page.total)} {page.total === 1 ? "role" : "roles"}
        </p>
        <p className="label text-ink-3">Updated {dateTime(stats.data_as_of)}</p>
      </div>

      {page.postings.length === 0 ? (
        <p className="py-16 text-center font-display text-2xl text-ink-3">
          No open roles match those filters.
        </p>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {page.postings.map((posting) => (
            <JobCard key={posting.posting_key} posting={posting} />
          ))}
        </div>
      )}

      {page.total > PAGE_SIZE && (
        <div className="flex items-center justify-between gap-4 border-t border-rule pt-4">
          {offset > 0 ? (
            <Link
              href={withParams(filters, { offset: String(Math.max(offset - PAGE_SIZE, 0)) })}
              className="label border border-rule px-4 py-2 hover:bg-paper-2"
            >
              ← Previous
            </Link>
          ) : (
            <span />
          )}
          <span className="label text-ink-3">
            {count(offset + 1)}–{count(offset + page.postings.length)} of {count(page.total)}
          </span>
          {!lastPage ? (
            <Link
              href={withParams(filters, { offset: String(offset + PAGE_SIZE) })}
              className="label border border-rule px-4 py-2 hover:bg-paper-2"
            >
              Next →
            </Link>
          ) : (
            <span />
          )}
        </div>
      )}
    </div>
  );
}
