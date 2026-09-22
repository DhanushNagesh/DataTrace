// Every call here runs on the server (React Server Components and route handlers only).
// The browser never learns the API Gateway URL, so the API needs no CORS configuration
// and the throttle sees Vercel's regional IPs rather than every visitor's.

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
  limit?: number;
  offset?: number;
};

// Only these keys are forwarded. Anything else in the URL (a stray utm tag, a hand-typed param)
// is dropped rather than passed through to the API, which would 400 or split the Vercel cache.
const POSTING_PARAMS = [
  "q", "company", "role_family", "seniority", "work_mode", "source", "min_salary", "sort",
  "limit", "offset",
] as const;

export const getPostings = (query: PostingsQuery) => {
  const params: Record<string, string | number | undefined> = {};
  for (const key of POSTING_PARAMS) params[key] = query[key];
  return get<PostingsPage>("/postings", params);
};
