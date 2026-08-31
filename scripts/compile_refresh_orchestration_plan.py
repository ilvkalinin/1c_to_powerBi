#!/usr/bin/env python3
"""Validate and print the fail-closed VM-2 refresh-orchestration plan."""

from __future__ import annotations

import argparse
import json
from collections import defaultdict, deque
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "config/project_refresh_orchestration.json"
ALLOWED_STATUSES = {"BLOCKED", "READY_FOR_REVIEW", "AUTOMATION_APPROVED"}


def load_manifest(path: Path) -> dict[str, object]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != 1:
        raise RuntimeError("Unsupported orchestration manifest schema")
    if manifest.get("execution_host") != "VM-2":
        raise RuntimeError("Only VM-2 is an allowed orchestration host")
    return manifest


def topological_order(jobs: list[dict[str, object]]) -> list[str]:
    by_id = {str(job["id"]): job for job in jobs}
    if len(by_id) != len(jobs):
        raise RuntimeError("Duplicate orchestration job id")
    dependents: dict[str, list[str]] = defaultdict(list)
    indegree = {job_id: 0 for job_id in by_id}
    for job_id, job in by_id.items():
        for dependency in job["dependencies"]:
            dependency = str(dependency)
            if dependency not in by_id:
                raise RuntimeError(f"{job_id} references absent dependency {dependency}")
            dependents[dependency].append(job_id)
            indegree[job_id] += 1
    ready = deque(sorted(job_id for job_id, degree in indegree.items() if degree == 0))
    order: list[str] = []
    while ready:
        job_id = ready.popleft()
        order.append(job_id)
        for dependent in sorted(dependents[job_id]):
            indegree[dependent] -= 1
            if indegree[dependent] == 0:
                ready.append(dependent)
    if len(order) != len(by_id):
        raise RuntimeError("Orchestration dependency graph has a cycle")
    return order


def validate(manifest: dict[str, object]) -> tuple[list[dict[str, object]], list[str]]:
    jobs = manifest.get("jobs")
    if not isinstance(jobs, list) or not jobs:
        raise RuntimeError("Manifest has no jobs")
    typed_jobs = [job for job in jobs if isinstance(job, dict)]
    if len(typed_jobs) != len(jobs):
        raise RuntimeError("Manifest job is not an object")
    targets: list[str] = []
    for job in typed_jobs:
        for key in ("id", "refresh_class", "scheduling_status"):
            if not isinstance(job.get(key), str) or not job[key]:
                raise RuntimeError(f"Job lacks non-empty {key}")
        if job["scheduling_status"] not in ALLOWED_STATUSES:
            raise RuntimeError(f"{job['id']} has invalid scheduling status")
        entrypoint = job.get("entrypoint")
        entrypoint_status = job.get("entrypoint_status", "VERSIONED")
        if entrypoint_status == "VERSIONED":
            if not isinstance(entrypoint, str) or not entrypoint:
                raise RuntimeError(f"{job['id']} lacks a versioned entrypoint")
            path = ROOT / entrypoint
            if not path.is_file():
                raise RuntimeError(f"{job['id']} entrypoint is absent: {path}")
        elif entrypoint_status == "UNVERSIONED_BLOCKED":
            if entrypoint is not None or job["scheduling_status"] != "BLOCKED":
                raise RuntimeError(f"{job['id']} has invalid unversioned entrypoint state")
        else:
            raise RuntimeError(f"{job['id']} has invalid entrypoint status")
        if not isinstance(job.get("dependencies"), list) or not isinstance(job.get("targets"), list):
            raise RuntimeError(f"{job['id']} has invalid targets/dependencies")
        targets.extend(str(target) for target in job["targets"])
    if len(targets) != int(manifest["physical_object_count"]):
        raise RuntimeError("Physical-object count differs from job targets")
    duplicates = sorted({target for target in targets if targets.count(target) != 1})
    if duplicates:
        raise RuntimeError("Physical target belongs to multiple jobs: " + ", ".join(duplicates))
    order = topological_order(typed_jobs)
    return typed_jobs, order


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--plan", action="store_true", help="validate and print only; no runner is invoked")
    args = parser.parse_args()
    if not args.plan:
        parser.error("Only --plan is available in the planning package; runner execution is forbidden")
    manifest = load_manifest(args.manifest)
    jobs, order = validate(manifest)
    statuses = {status: sum(job["scheduling_status"] == status for job in jobs) for status in ALLOWED_STATUSES}
    if statuses["AUTOMATION_APPROVED"]:
        raise RuntimeError("Planning package forbids automation-approved jobs")
    print(
        "ORCHESTRATION_PLAN_PASS "
        f"physical_objects={manifest['physical_object_count']} jobs={len(jobs)} "
        f"views_not_jobs={len(manifest['view_not_job'])} blocked={statuses['BLOCKED']}"
    )
    print("DAG_ORDER " + ",".join(order))


if __name__ == "__main__":
    main()
