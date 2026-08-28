# Авторизация Stage 3 technical review: tie-break client-start cohort

- Дата: 2026-08-28
- Пакет: `fitness_funnel_client_start_stage3_term_tiebreak_review_2026-08-28`
- Этап: `STAGE_3_TECHNICAL_SQL_REVIEW`
- Отчёт: № 11 «Фитнес воронка» (`fitness_funnel`)
- Основание: пользователь подтвердил пакет в задаче 2026-08-28 после решения
  BR-048: поздняя дата покупки, затем больший срок договора.

## Разрешённый scope

Только read-only техническая доработка `mart.fitness_funnel_client_start`:

1. в fresh `REPEATABLE READ, READ ONLY` snapshot через project retry helper
   выполнить на полном approved horizon независимый контроль равенств обоих
   рангов: `Reference59.Fld674 DESC`, затем `Reference59.Fld693 DESC`;
2. если residual tie = 0, обновить локальный immutable set — source extract,
   FF-S01—FF-S03 controls, guarded runner и target reconciliation — так, чтобы
   selector был детерминированным и проверяемым независимо от extract;
3. выполнить controls на полном горизонте и измерить точный revised source
   extract безопасным `EXPLAIN (ANALYZE, BUFFERS)` на representative window;
4. сохранить mapping, data contract, BR-048, SQL-review execution evidence,
   статические проверки runner и закрыть пакет.

## Запрещённые операции

Не разрешены target connection, DDL, DML, COPY, transport, создание
`mart.fitness_funnel_client_start`, Power BI/PBIT/M/DAX changes, source
DDL/indexes или raw replication. При ненулевом residual tie пакет закрывается
`DECISION_REQUIRED`; никакой fallback не выбирается.

## Критерий закрытия

Полный независимый source control доказывает zero residual ties по обоим
рангам, revised extract имеет один row на `(client_key, membership_start_date)`,
атрибуты берутся только из выбранного договора, все null/future/key controls
равны нулю, а source plan не показывает material regression. Иначе —
документированный `DECISION_REQUIRED` без physical SQL.
