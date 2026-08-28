# `mart.promo_application`: Stage 2 read-only cardinality package

Статус: `ACTIVE / VALIDATION_IN_PROGRESS`.

## Одобренный scope

Пользователь 2026-08-28 подтвердил отдельный пакет для отчёта «Отчёт по
промокодам» и проектируемого продукта `mart.promo_application`.

- Выполнить только `PC-V02` и `PC-V04` из
  [`promo_codes_2026-08-13.sql`](../source_metadata/validation_sql/promo_codes_2026-08-13.sql)
  в отдельных коротких сессиях `BEGIN READ ONLY` через
  `scripts.mart_connection.connect_with_retry`.
- Проверить сохранение технических discount-movements после current document-line
  joins, а также parent/action, duplicate-discount и gift-join cardinality.
- Сохранить агрегатные результаты, время выполнения и snapshot provenance;
  обновить mapping, ADR, data contract и evidence только по фактам проверки.

## Границы автономной работы

Не входят в пакет: DDL/DML, создание `mart.promo_application`, перенос или
копирование строк, full-range extract, изменение SQL/M/DAX, Power BI,
дедупликация или любое новое business rule. Источник `gymdb` доступен только
ролью `gymdb_readonly`; запросы не возвращают PII и raw identifiers.

## Ожидания, зафиксированные до запуска

| Control | Базовое независимое evidence | Ожидание для live проверки | Допуск |
|---|---|---|---|
| PC-V02 | SV-091, 2026-08-13: 7 535 технических ключей, 7 568 joined rows, excess 33 | Повторно измерить тот же bounded June-2026 current-M join; любое значение `join_excess_rows > 0` — сохранённый one-to-many risk, не повод для дедупликации | Точный result не объявляется PASS без независимого control; сравнить с SV-091 как с историческим evidence |
| PC-V04 | SV-091, 2026-08-13: action parent/null-discount 0/0; 902 duplicate groups; 11 698 gift keys, 4 509 joined rows, excess 406 | `action_rows_without_parent = 0`; остальные значения повторно измерить как source observations; positive gift excess — сохранённый one-to-many risk | Parent orphan = 0 — проверяемая integrity-инварианта; другие результаты не меняют current M |

## Критерий закрытия

Оба controls завершены или честно зафиксированы `BLOCKED`; evidence содержит
expected/actual/status/provenance; mapping и ADR отражают факты без смены
методики. Пакет закрывается рекомендацией о возможности либо невозможности
Stage 3 planning. При обнаруженной кратности итог остаётся `DECISION_REQUIRED`:
первый релиз обязан сохранить legacy `MAX`/`SUM`/`Table.Distinct` по BR-018.
