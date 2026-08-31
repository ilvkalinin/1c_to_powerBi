# Incremental design: `mart.contract_usage`

Статус: `INCREMENTAL_CANDIDATE / IMPLEMENTATION_NOT_EXECUTED`.

The approved remediation removed the unconfirmed `is_finalized`,
`finalized_month`, mutable cutoff and mutable-only replacement semantics. The
separate `load_contract_usage_incremental.py` therefore does not reintroduce a
time cutoff. It calculates the reviewed exact current BR-003 source aggregate,
compares two deterministic fingerprints for every `contract_id`, and targets
only changed keys.

Source-absent target keys are deleted in the same transaction. Current source
keys are copied into a temporary stage, checked for the contract grain and
interval/count invariants, then inserted after the key delete. A pre-commit
full key fingerprint check must equal the source snapshot; failures roll back.
The existing `load_contract_usage.py` remains an untouched full-rebuild runner.

The technical review measured the exact source extract at 31,788 rows and
1.514 s without disk or temporary I/O. No incremental SLA is claimed until a
write-run is separately measured. No DML, COPY or scheduler task ran in this
design package.
