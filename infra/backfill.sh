#!/usr/bin/env bash
# Rebuilds intermediate.int_postings_seen and the marts on it from all of raw.job_postings, in
# several dbt Lambda invokes. This is the prod equivalent of
#   dbt build --full-refresh --select int_postings_seen+
# which stopped fitting in Lambda's 900s once raw passed ~35 days (805s on Oct 22 2026).
# Needed after changing a staging macro such as is_us_location, so history is reclassified.
#
#   infra/dbt.sh '{"command":["parse"]}'             # deploy the current dbt project first
#   infra/backfill.sh 2026-09-27 2026-10-07 2026-10-17 2026-10-27
#   infra/backfill.sh --resume 2026-10-17 2026-10-27  # after a failed chunk: no full refresh
#
# Each date is an upper bound on loaded_at (UTC) for one chunk, passed as the backfill_until var.
# The first chunk recreates the table; later ones merge into it like a normal incremental run;
# a final plain build picks up everything after the last date and rebuilds the marts and tests.
# Raw ran ~23s per day of loads on Oct 22, so 10-day chunks take ~4 minutes. Each run prints its
# duration; shrink the chunks if one gets near 600s, since a Lambda timeout leaves its queries
# running on RDS. Get the first load date with infra/db_admin.sh '{"scripts":["check_data.sql"]}'.
#
# The marts keep serving the old data until the final build, so the API never sees a partial
# table. Run it well clear of the 06:00 America/Los_Angeles pipeline: a daily build that starts
# mid-backfill would try to merge all the remaining history in one invoke.
#
# Cost: Lambda at 2 GB is ~$0.0000267/s, so a full backfill (~20 minutes) is about 3 cents.
set -euo pipefail
export AWS_REGION="${AWS_REGION:-us-east-2}"

FUNCTION=datatrace-dbt
resume=false
if [ "${1-}" = "--resume" ]; then
  resume=true
  shift
fi
if [ $# -eq 0 ]; then
  sed -n '2,/^set -e/p' "$0" | sed '$d'
  exit 1
fi

hour=$(TZ=America/Los_Angeles date +%-H)
if [ "$hour" -ge 5 ] && [ "$hour" -lt 8 ]; then
  echo "refusing to start within the 06:00 Los Angeles pipeline window" >&2
  exit 1
fi

run() { # json command array
  local out started status
  out=$(mktemp)
  started=$(date +%s)
  echo "dbt $1"
  status=$(aws lambda invoke --function-name "$FUNCTION" --cli-read-timeout 0 \
    --cli-binary-format raw-in-base64-out --payload "{\"command\":$1}" \
    --query 'FunctionError' --output text "$out")
  echo "  $(($(date +%s) - started))s: $(cat "$out")"
  if [ "$status" != "None" ]; then
    echo "chunk failed; once RDS is idle, rerun with --resume from this chunk's date" >&2
    exit 1
  fi
}

prev=""
for until in "$@"; do
  if ! [[ $until =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || [[ ! $until > $prev ]]; then
    echo "dates must be YYYY-MM-DD in ascending order: $*" >&2
    exit 1
  fi
  prev=$until
done

refresh=()
$resume || refresh=('"--full-refresh",')
for until in "$@"; do
  run "[\"run\",${refresh[*]-}\"--select\",\"int_postings_seen\",\"--vars\",\"{backfill_until: '$until'}\"]"
  refresh=()
done
run '["build","--select","int_postings_seen+"]'
