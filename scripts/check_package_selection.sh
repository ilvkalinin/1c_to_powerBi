#!/bin/sh
# Reject package targets whose latest checkpoint is already closed.
set -eu

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <stage> <report_id> [<report_id> ...]" >&2
  exit 2
fi

stage="$1"
shift
ledger=".agents/report_checkpoint_ledger.tsv"
project_gate=".agents/project_stage_gate.tsv"

if [ ! -r "$project_gate" ]; then
  echo "PACKAGE SELECTION REJECTED: missing $project_gate" >&2
  exit 2
fi

project_state=$(awk -F '\t' '$1 !~ /^#/ && $1 == "global_stage_gate" { print $2; exit }' "$project_gate")
allowed_stage=$(awk -F '\t' '$1 !~ /^#/ && $1 == "global_stage_gate" { print $3; exit }' "$project_gate")
allowed_report_ids=$(awk -F '\t' '$1 !~ /^#/ && $1 == "global_stage_gate" { print $4; exit }' "$project_gate")
project_reason=$(awk -F '\t' '$1 !~ /^#/ && $1 == "global_stage_gate" { print $5; exit }' "$project_gate")
if [ "$project_state" = "OPEN" ]; then
  :
elif [ "$project_state" = "READONLY_REVIEW_AUTHORIZED" ] && [ "$stage" = "$allowed_stage" ]; then
  :
else
  echo "PACKAGE SELECTION REJECTED: global stage gate is ${project_state:-MISSING}; ${project_reason:-no documented release}" >&2
  exit 1
fi

if [ ! -r "$ledger" ]; then
  echo "PACKAGE SELECTION REJECTED: missing $ledger" >&2
  exit 2
fi

failed=0
for report_id in "$@"; do
  if [ "$project_state" = "READONLY_REVIEW_AUTHORIZED" ]; then
    case ",$allowed_report_ids," in
      *,"$report_id",*) ;;
      *)
        echo "PACKAGE SELECTION REJECTED: $report_id is outside the authorized global read-only review" >&2
        failed=1
        continue
        ;;
    esac
  fi

  row=$(awk -F '\t' -v id="$report_id" -v wanted_stage="$stage" \
    '$1 !~ /^#/ && $1 == id && $2 == wanted_stage { print; exit }' "$ledger")
  if [ -z "$row" ]; then
    echo "PACKAGE SELECTION REJECTED: $report_id has no ledger row for $stage" >&2
    failed=1
    continue
  fi

  selection_state=$(printf '%s\n' "$row" | awk -F '\t' '{ print $5 }')
  trigger=$(printf '%s\n' "$row" | awk -F '\t' '{ print $6 }')
  if [ "$selection_state" = "READY_FOR_NEW_CONTROL" ] && [ -n "$trigger" ] && [ "$trigger" != "-" ]; then
    echo "PACKAGE SELECTION ALLOWED: $report_id — $trigger"
  else
    echo "PACKAGE SELECTION REJECTED: $report_id is $selection_state; $trigger" >&2
    failed=1
  fi
done

exit "$failed"
