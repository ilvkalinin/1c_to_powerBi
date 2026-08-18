#!/usr/bin/env bash
# Fail closed only for a completed-work summary or final response. Intermediate
# commentary uses the lighter end-with-next-action rule from communication.md.
set -euo pipefail

if [[ $# -gt 1 ]]; then
  printf 'Usage: %s [response-file]\n' "$0" >&2
  exit 2
fi

if [[ $# -eq 1 ]]; then
  [[ -r "$1" ]] || { printf 'RESPONSE FORBIDDEN: unreadable response file.\n' >&2; exit 2; }
  response=$(<"$1")
else
  response=$(cat)
fi

if [[ -z "${response//[[:space:]]/}" ]]; then
  printf 'RESPONSE FORBIDDEN: empty response.\n' >&2
  exit 1
fi

made=$(grep -Ec '^Сделано:[[:space:]]*[^[:space:]].*$' <<<"$response" || true)
result=$(grep -Ec '^Результат:[[:space:]]*[^[:space:]].*$' <<<"$response" || true)
next=$(grep -Ec '^Дальше:[[:space:]]*[^[:space:]].*$' <<<"$response" || true)

if [[ "$made" -ne 1 || "$result" -ne 1 || "$next" -ne 1 ]]; then
  printf 'RESPONSE FORBIDDEN: require exactly one non-empty «Сделано:», «Результат:», and «Дальше:» line.\n' >&2
  exit 1
fi

made_line=$(grep -nE '^Сделано:[[:space:]]*[^[:space:]].*$' <<<"$response" | cut -d: -f1)
result_line=$(grep -nE '^Результат:[[:space:]]*[^[:space:]].*$' <<<"$response" | cut -d: -f1)
next_line=$(grep -nE '^Дальше:[[:space:]]*[^[:space:]].*$' <<<"$response" | cut -d: -f1)
if (( made_line >= result_line || result_line >= next_line )); then
  printf 'RESPONSE FORBIDDEN: sections must be ordered «Сделано → Результат → Дальше».\n' >&2
  exit 1
fi

last_nonempty=$(awk 'NF { line=$0 } END { print line }' <<<"$response")
if [[ "$last_nonempty" != Дальше:* ]]; then
  printf 'RESPONSE FORBIDDEN: «Дальше:» must be the final non-empty line.\n' >&2
  exit 1
fi

if grep -Eq '^Дальше:.*(готов|жду|продолжу|можно двигаться дальше)[.![:space:]]*$' <<<"$response"; then
  printf 'RESPONSE FORBIDDEN: «Дальше:» must name one concrete action or a self-contained question.\n' >&2
  exit 1
fi

printf 'RESPONSE CONTRACT ALLOWED.\n'
