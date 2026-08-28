# Авторизация physical admission BR-048: `mart.fitness_funnel_client_start`

Пользователь 2026-08-28 подтвердил physical package только для
`mart.fitness_funnel_client_start`: full source controls, measured derived
transport, target DDL/atomic load, FF-R01—FF-R07, target plan and atomic rerun.
Scope uses the immutable BR-048 selector reviewed in
`fitness_funnel_client_start_stage3_term_tiebreak_review_execution_2026-08-28.md`.
`mart.fitness_funnel_client_outcome`, Power BI and source DDL/indexes are
prohibited. Any error rolls back the target transaction and removes temporary
COPY data. Closure requires zero deviations in both source snapshots, two
atomic runs and target read-plan evidence.
