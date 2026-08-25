# «Клиентская база»: read-only review охвата детских пакетов

- Пакет: `client_base_package_coverage_2026-08-25`
- Этап: `STAGE_2_SERVER_VALIDATION`
- Авторизация: [package authorization](client_base_package_coverage_review_authorization_2026-08-25.md)
- Статус: `VALIDATED` для факта отсутствующей ветви; `DECISION_REQUIRED` для будущего способа её включения.
- Границы: только `REPEATABLE READ READ ONLY`; DDL/DML/COPY, изменения
  `mart.client_base_daily` и Power BI не выполнялись.

## Подтверждённый mapping и reuse-review

| Домен | Current source/target | Результат review | Статус |
|---|---|---|---|
| Абонементная ветвь | `Reference59 → mart.client_base_daily` | extract использует только `Reference59`, клиента договора и две независимые `club/network` дедупликации | CONFIRMED |
| Детский пакет | `Document346.VT4913 → Document346 → Reference59 → child Reference141X1` | источник ребёнка, взрослого договора, клуба и package interval подтверждён; ребёнок — `VT4913.Fld4916`, клуб/окончание — взрослый `Reference59` | CONFIRMED |
| Целевая витрина | `mart.client_base_daily` | семь колонок содержат только scope/date/club/age/gender/count; нет пакетной source-ветви, package type или идентификатора для включения детей | CONFIRMED gap |
| Reuse BR-037 | sales/return правило вовлечения | не применяется к client base: BR-037 прямо требует отдельного пакета для этой интеграции | CONFIRMED boundary |

Следовательно, пакетные строки не «теряются» при агрегации: они вообще не
входят в текущий source extract. Их будущая возрастная группа должна быть
`Дети` по уже подтверждённому пользовательскому правилу, но способ определения
действительности пакета (current Power BI branch либо BR-037 sales/return)
требует отдельного решения до реализации.

## Source controls

Выполненный SQL: [client_base_package_coverage_2026-08-25.sql](../source_metadata/validation_sql/client_base_package_coverage_2026-08-25.sql).
Все результаты агрегированы; client IDs и PII не выводились.

| Control | Результат | Статус |
|---|---:|---|
| CB-PKG-001, 2026-08-25: текущая membership base, club/network | 79 566 / 79 499 | VALIDATED |
| CB-PKG-001: активные package children, club/network | 15 847 / 15 814 | VALIDATED |
| CB-PKG-001: package-only gap, club/network | **15 759 / 15 714** | VALIDATED — материальный gap |
| CB-PKG-002, BR-003 `[2025-01-01, 2027-01-01)`: дней с gap, club/network | 730 / 730 | VALIDATED |
| CB-PKG-002: package-only client-days, club/network | **5 154 048 / 5 141 198** | VALIDATED — текущая витрина неполна на всём горизонте |
| CB-PKG-002: максимальный суточный gap, club/network | 15 759 / 15 714 | VALIDATED |
| CB-PKG-003: уникальность `(receipt,line)` | 47 388 / 47 388 | VALIDATED |
| CB-PKG-003: orphan receipt/contract | 0 / 0 | VALIDATED |
| CB-PKG-003: orphan child/adult/club | 9 933 / 1 / 385 | VALIDATED observation; orphan children не входят в eligible universe |
| CB-PKG-003: marked / unposted receipt | 482 / 1 653 | VALIDATED observation; current branch не вводит новый state predicate |
| CB-PKG-003: current status rows / invalid adult interval | 41 497 / 2 027 | VALIDATED; interval predicate исключает второе значение |

В `VT4913` встречаются 1 746 строк с `NULL`/sentinel activation взрослого
договора. Current package predicate сохраняет историческое `OR`; review не
заменяет его на строгий `AND`, чтобы не изменить результат без решения.

## Target и производительность

Target на 2026-08-25 содержит `club = 79 147`, `network = 79 083`; это
снимок ранее согласованной абонементной загрузки, а не same-MVCC snapshot с
нынешним source, поэтому разницу с live source не объявляем reconciliation
deviation. Независимый target contract прошёл: 1 657 353 rows,
`duplicate_keys = 0`, `contract_violations = 0`, `rows_outside_horizon = 0`.

Перед full control выполнена безопасная выборка на 2026-08-25:
`EXPLAIN (ANALYZE, BUFFERS)` — 2 885.191 ms, shared hit/read blocks
665 182/16 970, без временных файлов. Затем масштабированный control по
BR-003 выполнился за 21 545.558 ms (planning 9.104 ms), shared hit/read
1 377 649/0, temporary read/written blocks 74 674/164 735. Это приемлемый
read-only audit, но spill показывает, что данный control нельзя использовать
как ежедневный load query без отдельного performance package. Target contract
scan выполнился за 6 350.081 ms; это не измерение refresh SLA.

## Закрытие и дальнейшее решение

`mart.client_base_daily` оставлена без изменений и сохраняет current
абонементный результат по BR-018. Для будущего implementation package нужен
выбор одного из двух доказуемо разных source rules: воспроизвести current
package branch со статусом чека и историческим predicate или расширить
client-base scope BR-037 положительными, не возвращёнными продажами. В обоих
вариантах package-only children включаются с возрастной группой `Дети`, а
перед DDL/DML обязателен sample-first performance review и exact reconciliation
against approved control values.
