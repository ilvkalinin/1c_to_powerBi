#!/usr/bin/env bash
# Fail closed: exit non-zero unless the tracked autonomous package is CLOSED,
# every report is COMPLETE, and each completion commit is reachable from HEAD.
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
state_file="$repo_root/.agents/active_package.tsv"

if [[ ! -f "$state_file" ]]; then
  printf 'FINAL FORBIDDEN: no active-package state file: %s\n' "$state_file" >&2
  exit 1
fi

package_status=$(awk -F '\t' '$1 !~ /^#/ && $1 != "package_id" && NF == 4 { print $3; exit }' "$state_file")
if [[ "$package_status" != "CLOSED" ]]; then
  printf 'FINAL FORBIDDEN: package status is %s, not CLOSED.\n' "${package_status:-MISSING}" >&2
  awk -F '\t' '$1 !~ /^#/ && $1 != "report_id" && NF == 3 && $2 != "COMPLETE" { printf "  %s: %s\n", $1, $2 > "/dev/stderr" }' "$state_file"
  exit 1
fi

failed=0
while IFS=$'\t' read -r report status commit; do
  [[ -z "$report" || "$report" == \#* || "$report" == "report_id" ]] && continue
  if [[ "$status" != "COMPLETE" || "$commit" == "-" || -z "$commit" ]]; then
    printf 'FINAL FORBIDDEN: %s is %s (commit: %s).\n' "$report" "$status" "$commit" >&2
    failed=1
  elif ! git merge-base --is-ancestor "$commit" HEAD; then
    printf 'FINAL FORBIDDEN: completion commit %s for %s is not reachable from HEAD.\n' "$commit" "$report" >&2
    failed=1
  fi
done < "$state_file"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

printf 'FINAL ALLOWED: tracked package is CLOSED and every report commit is in HEAD.\n'
