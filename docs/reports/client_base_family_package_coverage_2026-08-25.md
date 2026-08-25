# CBF-PKG-COVERAGE-001: child-package coverage of the client-base family

- Package: `client_base_family_package_coverage_2026-08-25`
- Stage: `STAGE_2_SERVER_VALIDATION` (read-only review)
- Executed: 2026-08-25
- Status: `VALIDATED` for the current family contract; physical deferred facts
  are `NOT_EXECUTED`, not represented as loaded coverage.

## Scope boundary

The client-base family comprises `mart.client_base_daily`,
`mart.client_base_snapshot`, and `mart.client_base_retention`. `Работа с
посещаемостью`, `Титульный лист`, `KPI Фитнеса`, and hourly attendance reuse
`mart.client_base_daily` as a denominator; they do not own a second
client-base universe and must not replicate the child-package source branch.

## Results

| Fact | Physical status | Package coverage | Evidence | Result |
|---|---|---|---|---|
| `mart.client_base_daily` | exists; BR-038 rebuild/rerun validated | BR-037 sales/return and maximum-start branch; BR-038 `Дети`/priority branch | `client_base_daily_extract.sql`, independent controls, S3-CBD-PKG-001 | `CONFIRMED` |
| `mart.client_base_snapshot` | `to_regclass = NULL`; implementation deferred | mandatory BR-037/BR-038 source universe and priority now explicit in ADR/mapping/contract | ADR-0002, `client_base.md`, data contract | `CONFIRMED design / NOT_EXECUTED physical` |
| `mart.client_base_retention` | `to_regclass = NULL`; implementation deferred | mandatory BR-037/BR-038 baseline/current universe before cohort dedupe and semi-join | ADR-0002, retention mapping, data contract | `CONFIRMED design / NOT_EXECUTED physical` |

`mart.client_base_daily` final rerun controls were 1 712 574 rows, 1 460 daily
scope controls, 0 contract/key/horizon deviations, and BR-038 226 025 club /
225 846 network child-package client-days aged 14+ or unknown. The target
constraint is validated. Power BI was not changed.

## Reconciliation interpretation

There is no second physical fact missing package rows: snapshot and retention
are not created. Their future implementation cannot use a `Reference59`-only
universe; the accepted source contract now requires exact BR-037/BR-038 reuse
before their respective client dedupe. A future implementation package must
obtain its own source controls, DDL/load/reconciliation/rerun approval.
