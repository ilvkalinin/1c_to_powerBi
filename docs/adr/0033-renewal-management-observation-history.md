# ADR-0033: наблюдаемая история «Управления продлением»

- Статус: `ACCEPTED / Stage 3 forward-observation initial load validated`
- Дата: 2026-08-29
- Потребитель: будущая историческая аналитика «Управления продлением»

## Контекст

`mart.renewal_management_contract` воспроизводит current Power BI: после
каждого refresh он может изменить next-contract, latest interaction, rating,
tenure и funnel fields договора, который закончился давно. Это верно для
оперативного результата, но не отвечает на вопрос «что система показывала на
ту дату».

Построить новые постоянные копии `Reference59`, `Reference67`, visits или
info-registers на VM-2 нельзя: это raw replication без доказанного общего
grain. Текущий source metadata также не доказывает версионность Reference59
и task-side CRM attributes для реконструкции 2025 года.

## Решение

После успешного refresh current fact хранить отдельный append-only объект:

> `mart.renewal_management_contract_observation`.

Grain: один исходный договор × момент наблюдаемого изменения. Object использует
только same-grain current mart; он не читает и не дублирует raw 1С на VM-2.

Поток:

> atomic refresh current contract mart → compare with latest observation →
> append changed/removed compact analytic states → Power BI as-of selector.

В history не записываются PII и source raw rows. Append только deltas ограничит
рост по сравнению с ежедневной полной копией всех ~241k договоров. Начальный
baseline и любые later corrections видны как observation versions; snapshot
semantics — «as observed after successful refresh», а не «непрерывное время
1С».

## Отклонённые варианты

1. Три VM-2 base tables contracts/visits/interactions — raw duplication и
   разношерстные grain/refresh semantics.
2. Полный daily copy current fact — умножает примерно 241k строк на число
   дней без необходимости фиксировать неизменные значения.
3. Ретроспективно назвать текущие Reference59/CRM значения snapshot 2025 —
   недостоверно без source history/backdating evidence.

## Consequences and review triggers

Существующая `mart.renewal_management_contract` не меняется. Новый object,
loader, scheduler, DDL/DML, retention, `observed_at` timezone и Power BI
role-playing/as-of UX требуют отдельного Stage 2/3 пакета.

ASOF-V01—V07 (2026-08-29) validated the unique upstream key and no tied
rating/tenure periods. The source cohort differed by two rows from the last
committed mart snapshot, so observation must read the parent target only after
its successful commit. User accepts either interaction timestamp; the first
release keeps current-M `Reference67.Fld820` (started). Retrospective effective-
date reconstruction remains excluded: neither a historical task funnel/fail
state nor `Reference59` creation/backdating/correction history is confirmed.

Initial baseline loaded 240,967 PII-free observation rows at
`2026-08-29 15:51:34+03`; the immediate atomic append rerun inserted zero rows
and reconciled. For an as-of read the reviewed `MAX(observed_at)` plus primary-
key join is result-equal to `DISTINCT ON ... DESC` and measured 460.592 ms
versus 2,755.651 ms. No additional index is required or created in this
package. Retention, scheduling and all Power BI changes remain separate work.
