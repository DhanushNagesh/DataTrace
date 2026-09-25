// The only facet values the marts can produce. dbt's role_family_label and seniority_label
// macros define the first two; keep them in step. Both the postings page and the API client
// read these: the page to render the facets, the client to drop anything it didn't render.

export const ROLE_FAMILIES = [
  "Data Engineering", "Data Science / ML", "Data Analytics", "Sales & Success", "Marketing",
  "Design", "Product", "Engineering", "Corporate", "Operations & Support",
  "Hospitality & Fitness", "Healthcare", "Other",
];

export const SENIORITIES = [
  "Intern", "Entry", "Mid", "Senior", "Manager", "Staff+", "Director+", "Unspecified",
];

export const WORK_MODES = ["Remote (anywhere)", "Remote (US)", "On-site / hybrid"];

export const SOURCES = ["greenhouse", "lever", "ashby", "smartrecruiters", "rippling", "remoteok"];

export const MIN_SALARY = ["80000", "120000", "160000", "200000"];

export const SORTS: Record<string, string> = {
  newest: "Newest first",
  oldest: "Oldest first",
  salary_high: "Pay: high to low",
  salary_low: "Pay: low to high",
  company: "Company A–Z",
};

export const PAGE_SIZE = 24;

// The API rejects a larger offset outright; matching it here keeps the paging links inside
// the range rather than handing the user a 400 at the end of a big result set.
export const MAX_OFFSET = 10_000;

export const MAX_TEXT_LEN = 100;
