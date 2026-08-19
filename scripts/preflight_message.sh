#!/usr/bin/env bash
# One fail-closed gate for every final or completed-work summary.
set -euo pipefail

mode=${1:-}
response_file=${2:-}

if [[ $# -ne 2 || ( "$mode" != "--report-handoff" && "$mode" != "--direct-reply" ) ]]; then
  printf 'Usage: %s --report-handoff|--direct-reply <full-response-file>\n' "$0" >&2
  exit 2
fi

if [[ ! -r "$response_file" ]]; then
  printf 'MESSAGE FORBIDDEN: full response file is required and must be readable.\n' >&2
  exit 2
fi

repo_root=$(git rev-parse --show-toplevel)
"$repo_root/scripts/check_final_gate.sh" "$mode"
"$repo_root/scripts/check_response_contract.sh" "$response_file"

printf 'MESSAGE PRE-FLIGHT ALLOWED: %s and exact response text passed.\n' "$mode"
