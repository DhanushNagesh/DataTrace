import Link from "next/link";
import { Rule } from "@/components/rule";
import { Section } from "@/components/section";
import { StatTile } from "@/components/stat-tile";
import { DailyFlowChart } from "@/components/charts/daily-flow-chart";
import { RoleMixChart } from "@/components/charts/role-mix-chart";
import { SalaryRangeChart } from "@/components/charts/salary-range-chart";
import { SeniorityMixChart } from "@/components/charts/seniority-mix-chart";
import { TimeToCloseChart } from "@/components/charts/time-to-close-chart";
import {
  getDailyFlow,
  getRoleMix,
  getSalaryByRole,
  getSeniorityMix,
  getStats,
  getTimeToClose,
} from "@/lib/api";
import { count, dateTime } from "@/lib/format";

export default async function Dashboard() {
  // Six independent GETs, so they go out together rather than in series. Each is its own
  // Lambda invocation but they all hit the same warm container in practice.
  const [stats, roleMix, seniorityMix, salary, timeToClose, dailyFlow] = await Promise.all([
    getStats(),
    getRoleMix(),
    getSeniorityMix(),
    getSalaryByRole(),
    getTimeToClose(),
    getDailyFlow(),
  ]);

  const topFamilies = roleMix.slice(0, 6).map((r) => r.role_family);

  return (
    <div className="space-y-10">
      <Rule label="Job intelligence" />

      <div className="grid items-end gap-6 lg:grid-cols-[1.4fr_1fr]">
        <h1 className="font-display text-5xl leading-[1.05] sm:text-6xl">
          Every open role.
          <br />
          <em>Counted daily.</em>
        </h1>
        <div className="space-y-4">
          <p className="text-lg leading-relaxed text-ink-2">
            Six public job board APIs, pulled every morning, modelled in Postgres and aggregated
            before anyone asks. Data as of {dateTime(stats.data_as_of)}.
          </p>
          <Link href="/postings" className="label inline-block bg-accent px-6 py-3 text-on-accent">
            Browse open roles →
          </Link>
        </div>
      </div>

      <div className="grid gap-px border border-rule-soft bg-rule-soft sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Open postings" value={count(stats.open_postings)} />
        <StatTile label="New this week" value={count(stats.new_this_week)} hint="First seen in the last 7 days" />
        <StatTile label="Companies" value={count(stats.companies)} />
        <StatTile label="Sources" value={count(stats.sources)} hint="Public ATS APIs" />
      </div>

      <Section
        title="Role mix"
        note="Share of open postings by role family. Families come from the job title and department, bucketed in dbt."
      >
        <RoleMixChart rows={roleMix} />
      </Section>

      <Section
        title="Seniority within each role family"
        note="Each panel is a share of its own family, so panels are comparable in shape rather than in height. Six largest families shown."
      >
        <SeniorityMixChart rows={seniorityMix} families={topFamilies} />
      </Section>

      <Section
        title="Annualised pay by role family"
        note="p25 / median / p75 of the midpoint of the posted range, in USD. Only Ashby, Lever, Rippling and RemoteOK publish pay, so this is not a sample of the whole market. Families with fewer than 20 priced postings are dropped."
      >
        <SalaryRangeChart rows={salary} />
      </Section>

      <Section
        title="How long postings stay up"
        note="Closed postings only, so roles that fill slowly are under-counted until they actually close."
      >
        <TimeToCloseChart rows={timeToClose} />
      </Section>

      <Section
        title="Daily flow"
        note="Postings opened and closed each day, summed across role families. RemoteOK is excluded: its feed is a rolling window and can't say when a job closed."
      >
        <DailyFlowChart rows={dailyFlow} />
      </Section>
    </div>
  );
}
