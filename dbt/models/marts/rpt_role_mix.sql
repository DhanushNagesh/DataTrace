-- Share of open postings by role family, with how much of each bucket is remote and shows pay.
-- pct_with_salary mostly tracks source mix (Greenhouse and SmartRecruiters never publish pay), not role.
select
    {{ role_family_label('role_family') }} as role_family,
    count(*) as postings,
    round(100.0 * count(*) / sum(count(*)) over (), 1) as pct_of_all,
    -- Remote means the same thing here as rpt_postings.work_mode does: US-remote or remote-anywhere.
    -- Counting is_remote alone would drop the ~100 postings flagged only as remote-anywhere.
    round(100.0 * count(*) filter (where is_remote or is_remote_anywhere) / count(*), 1) as pct_remote,
    round(100.0 * count(salary_min) / count(*), 1) as pct_with_salary
from {{ ref('fct_job_postings') }}
where is_active is not false and not is_stale
group by 1
order by postings desc
