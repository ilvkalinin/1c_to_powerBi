# RM-ASOF-S1-001: Stage 1 execution

Статус: `COMPLETE`.

## Выполнено

- Локально сверены current-state contract mapping, ADR, Power BI boundary,
  source catalog и существующий project pattern effective intervals for
  `InfoRg5654`.
- Выполнен reuse review: только `mart.renewal_management_contract` совпадает
  по contract grain и current semantics; visits, KPI contract units and CRM
  core отвергнуты по grain/scope.
- Созданы mapping, ADR-0033 и Power BI contract для append-only observation
  fact. DDL/DML, PostgreSQL/1С sessions, SQL/EXPLAIN, COPY, schedule и Power BI
  changes не выполнялись.

## Решение

Первый будущий history product должен хранить forward observations after the
successful current fact refresh, а не называть текущий source реконструкцией
2025 года. Его rows появляются только при baseline/change/removal и позволяют
показать last observed state of a closed contract on любую сохранённую дату.

## Нерешённое и следующий trigger

`InfoRg5654.Period` имеет local proven as-of pattern, однако accuracy rating,
CRM task state and next-contract for a historic date пока не доказана. Для
ретроспективы нужны ASOF-V05—V07 и одно решение: что означает «известно на
дату» для next contract/interaction — activation, start, creation или иной
подтверждённый historical event.

Это не blocker для forward observation product design, но `BLOCKER` для claim
точного historical snapshot до первой сохранённой observation. Следующий
package может быть только явно одобренным Stage 2 server-validation пакетом
ASOF-V01—V07; no physical object is admitted by this Stage 1 result.
