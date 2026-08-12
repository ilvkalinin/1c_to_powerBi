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

if [ ! -r "$ledger" ]; then
  echo "PACKAGE SELECTION REJECTED: missing $ledger" >&2
  exit 2
fi

failed=0
for report_id in "$@"; do
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
