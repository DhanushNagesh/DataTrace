// Every call here runs on the server (React Server Components and route handlers only).
// The browser never learns the API Gateway URL, so the API needs no CORS configuration
// and the throttle sees Vercel's regional IPs rather than every visitor's.

import {
  MAX_OFFSET, MAX_TEXT_LEN, MIN_SALARY, PAGE_SIZE, ROLE_FAMILIES, SENIORITIES, SORTS, SOURCES,
  WORK_MODES,
} from "@/lib/facets";

const BASE = process.env.DATATRACE_API_URL;

// The pipeline rebuilds the marts once a day; 5 minutes matches the cache-control the
// Lambda already sends, so a burst of visitors costs one Lambda invocation.
const REVALIDATE = 300;

export type Stats = {
  open_postings: number;
  new_this_week: number;
  companies: number;
  sources: number;
  data_as_of: string;
};

export type RoleMix = {
  role_family: string;
  postings: number;
  pct_of_all: number;
  pct_remote: number;
  pct_with_salary: number;
};

export type SeniorityMix = {
  role_family: string;
  seniority: string;
  seniority_rank: number;
  postings: number;
  pct_of_family: number;
};

export type SalaryByRole = {
  role_family: string;
  n: number;
  sources: string;
  p25: number;
  median: number;
  p75: number;
};

export type TimeToClose = {
  role_family: string;
  closed_postings: number;
  median_days: number;
  p90_days: number;
};

export type DailyFlow = {
  day: string;
  role_family: string;
  open_postings: number;
  opened: number;
  closed: number;
  wow_change: number | null;
};

export type Posting = {
  posting_key: string;
  source: string;
  company_name: string;
  title: string;
  role_family: string;
  seniority: string;
  work_mode: string;
  location: string | null;
  salary_annual_mid_usd: number | null;
  url: string;
  // When the board says the role went up. first_seen_at is only when our ingest first saw it,
  // which is the same timestamp for every row until the warehouse has a few runs behind it.
  published_at: string | null;
  first_seen_at: string;
  days_listed: number | null;
};

export type PostingsPage = {
  postings: Posting[];
  // The filtered total, not the page: /postings computes it with a window function in the same
  // scan, so the facet bar can show a count without a second query.
  total: number;
  limit: number;
  offset: number;
};

async function get<T>(path: string, params?: Record<string, string | number | undefined>): Promise<T> {
  if (!BASE) throw new Error("DATATRACE_API_URL is not set");

  const url = new URL(path, BASE);
  for (const [key, value] of Object.entries(params ?? {})) {
    if (value !== undefined && value !== "") url.searchParams.set(key, String(value));
  }

  const res = await fetch(url, { next: { revalidate: REVALIDATE } });
  if (!res.ok) {
    // The Lambda never returns SQL or stack traces, so the body is safe to surface in logs
    throw new Error(`${path} returned ${res.status}: ${await res.text()}`);
  }
  return res.json() as Promise<T>;
}

export const getStats = () => get<Stats>("/stats");
export const getRoleMix = () => get<{ role_mix: RoleMix[] }>("/role-mix").then((d) => d.role_mix);
export const getSeniorityMix = () =>
  get<{ seniority_mix: SeniorityMix[] }>("/seniority-mix").then((d) => d.seniority_mix);
export const getSalaryByRole = () =>
  get<{ salary_by_role: SalaryByRole[] }>("/salary-by-role").then((d) => d.salary_by_role);
export const getTimeToClose = () =>
  get<{ time_to_close: TimeToClose[] }>("/time-to-close").then((d) => d.time_to_close);
export const getDailyFlow = () =>
  get<{ daily_flow: DailyFlow[] }>("/daily-flow").then((d) => d.daily_flow);

export type PostingsQuery = {
  q?: string;
  company?: string;
  role_family?: string;
  seniority?: string;
  work_mode?: string;
  source?: string;
  min_salary?: string;
  sort?: string;
  offset?: string;
};

// Only these values are forwarded. The API validates its own input, but a request that reaches
// it at all has already cost a Lambda invocation and a query against RDS, and has already taken
// its own slot in Vercel's data cache. Anything the page could not have produced is dropped
// here instead, so a crawler walking made-up query strings gets the same cached page as
// everyone else rather than a private trip to the database.
const oneOf = (value: string | undefined, allowed: readonly string[]) =>
  value && allowed.includes(value) ? value : undefined;

const text = (value: string | undefined) => value?.trim().slice(0, MAX_TEXT_LEN) || undefined;

// Offsets only ever come from our own paging links, so they are always a multiple of the page
// size. Snapping turns the 10,000 offsets the API accepts into the ~400 that can actually be
// reached, which is the difference between a bounded set of cache entries and an unbounded one.
const page = (value: string | undefined) => {
  const offset = Math.floor(Number(value ?? 0));
  if (!Number.isFinite(offset) || offset <= 0) return 0;
  return Math.min(offset - (offset % PAGE_SIZE), MAX_OFFSET);
};

export const getPostings = (query: PostingsQuery) =>
  get<PostingsPage>("/postings", {
    q: text(query.q),
    company: text(query.company),
    role_family: oneOf(query.role_family, ROLE_FAMILIES),
    seniority: oneOf(query.seniority, SENIORITIES),
    work_mode: oneOf(query.work_mode, WORK_MODES),
    source: oneOf(query.source, SOURCES),
    min_salary: oneOf(query.min_salary, MIN_SALARY),
    sort: oneOf(query.sort, Object.keys(SORTS)),
    limit: PAGE_SIZE,
    offset: page(query.offset),
  });
