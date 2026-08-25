#!/usr/bin/env bash
# Fail closed: exit non-zero unless the tracked autonomous package is CLOSED,
# every report is COMPLETE, and each completion commit is reachable from HEAD.
set -euo pipefail

mode=${1:-}
if [[ "$mode" != "--report-handoff" && "$mode" != "--direct-reply" ]]; then
  printf 'FINAL FORBIDDEN: progress messages belong to commentary, not final.\n' >&2
  printf 'Usage: %s --report-handoff | --direct-reply\n' "$0" >&2
  exit 2
fi

if [[ "$mode" == "--direct-reply" ]]; then
  printf 'DIRECT REPLY ALLOWED: this mode cannot be used for a report handoff.\n'
  exit 0
fi

repo_root=$(git rev-parse --show-toplevel)
state_file="$repo_root/.agents/active_package.tsv"

if [[ ! -f "$state_file" ]]; then
  printf 'FINAL FORBIDDEN: no active-package state file: %s\n' "$state_file" >&2
  exit 1
fi

package_row=$(awk -F '\t' '$1 !~ /^#/ && $1 != "package_id" && NF == 5 { print; exit }' "$state_file")
package_status=$(printf '%s\n' "$package_row" | awk -F '\t' '{ print $3 }')
approval_evidence=$(printf '%s\n' "$package_row" | awk -F '\t' '{ print $5 }')
if [[ "$package_status" != "CLOSED" ]]; then
  printf 'FINAL FORBIDDEN: package status is %s, not CLOSED.\n' "${package_status:-MISSING}" >&2
  awk -F '\t' '$1 !~ /^#/ && $1 != "report_id" && NF == 3 && $2 != "COMPLETE" { printf "  %s: %s\n", $1, $2 > "/dev/stderr" }' "$state_file"
  exit 1
fi

if [[ -z "$approval_evidence" || "$approval_evidence" == "-" ]]; then
  printf 'FINAL FORBIDDEN: package has no approval evidence for its full scope.\n' >&2
  exit 1
fi

if [[ "$approval_evidence" != /* && ! -f "$repo_root/$approval_evidence" ]]; then
  printf 'FINAL FORBIDDEN: approval evidence is not a readable project artifact: %s\n' "$approval_evidence" >&2
  exit 1
fi

failed=0
in_reports=0
while IFS=$'\t' read -r report status commit; do
  [[ "$report" == "report_id" ]] && { in_reports=1; continue; }
  [[ "$in_reports" -eq 0 || -z "$report" || "$report" == \#* ]] && continue
  if [[ "$status" != "COMPLETE" || "$commit" == "-" || -z "$commit" ]]; then
    printf 'FINAL FORBIDDEN: %s is %s (commit: %s).\n' "$report" "$status" "$commit" >&2
    failed=1
  elif [[ "$commit" != "SELF" ]] && ! git merge-base --is-ancestor "$commit" HEAD; then
    printf 'FINAL FORBIDDEN: completion commit %s for %s is not reachable from HEAD.\n' "$commit" "$report" >&2
    failed=1
  fi
done < "$state_file"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

printf 'FINAL ALLOWED: tracked package is CLOSED and every report commit is in HEAD.\n'
