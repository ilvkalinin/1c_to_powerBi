#!/usr/bin/env python3
"""Fail closed when a production mart runner bypasses connection retry policy."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNNERS = tuple(sorted((ROOT / "scripts").glob("load_*.py"))) + (
    ROOT / "scripts/refresh_revenue_chain.py",
)
DELEGATED_RUNNERS = {"refresh_revenue_chain.py"}


def is_compliant(path: Path, text: str) -> bool:
    if path.name in DELEGATED_RUNNERS:
        return "subprocess.run" in text and "load_" in text
    if "psycopg.connect" not in text:
        return "connect_with_retry" in text
    uses_shared_helper = "scripts.mart_connection import connect_with_retry" in text
    has_legacy_six_attempt_policy = (
        "for retry in range(6)" in text
        or "CONNECT_ATTEMPTS = 6" in text
    )
    return "connect_with_retry" in text and (uses_shared_helper or has_legacy_six_attempt_policy)


failed = []
for runner in RUNNERS:
    text = runner.read_text(encoding="utf-8")
    if is_compliant(runner, text):
        print(f"CONNECTION_RETRY_POLICY_PASS runner={runner.relative_to(ROOT)}")
    else:
        failed.append(runner.relative_to(ROOT))
        print(f"CONNECTION_RETRY_POLICY_FAIL runner={runner.relative_to(ROOT)}")

if failed:
    raise SystemExit("Connection retry policy missing: " + ", ".join(map(str, failed)))
