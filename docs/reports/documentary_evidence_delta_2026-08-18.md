# Документарная сверка после global read-only review — 2026-08-18

Статус: `DOCUMENTARY_AUDIT_COMPLETE / NO_SOURCE_QUERIES_RUN`.

> Актуальность. Это снимок документарной сверки на 2026-08-18. Контроли,
> выполненные 2026-08-19, не внесены в таблицы ниже; текущий остаток global
> gate задают `project_stage_gate.tsv`, `report_checkpoint_ledger.tsv` и
> [global checklist](global_gate_controls_checklist_2026-08-18.md).

## Цель и граница

Сверка сопоставляет реестр от 2026-08-14 с доказательствами и решениями,
добавленными до 2026-08-18. Она не запускает SQL, не меняет ни одного
согласованного правила и не снимает `GLOBAL_STAGE_GATE_BLOCKED`.

`CLOSED_CHECKPOINT` в ledger означает, что прежний Stage-2 control не нужно
повторять. Это не означает, что можно создавать витрину: report-level
reconciliation, SLA и прямо названные physical controls сохраняются в
реестре до отдельного полного review.

## Что изменилось относительно сверки 2026-08-14

| Отчёт | Новое доказательство / решение | Текущее следствие |
|---|---|---|
| Загрузка ОП | `SV-093` валидировал phone-row grain, кадровый `EXISTS` и наблюдение states. | Исходный технический gap закрыт; повторный Stage-2 контроль не нужен. |
| Отчёт по поступлениям | Исправление `SV-094` и `SV-096` подтвердили, что рекарринговая KPI-единица — `contract × payment_period`, а все движения группы суммируются. | Множественность движений не является дубликатом платежа; период не выводится из даты. Остаются states/sign, predecessor и независимая сверка текущего отчёта. |
| Продажа детских пакетов | `SV-095` и решение пользователя: для 38 строк без `VT4924` использовать `product_id = '0'`, `product_name = '0'`, `package_amount = 0`. | Gap price/product закрыт решением; возвраты и source states остаются отдельными controls. |
| Новички и гостевые визиты | `SV-097` подтвердил bounded document path; пользователь утвердил 12 ACCUNIQ-кодов и знаковое правило PBIT. | Для полного physical control теперь есть точный service scope; не выполнены статусы, ключи, full cardinality, outcome 0/44/45 и booking attribution. |
| Отчёт по обращениям | `SV-098`, `CR-V05D—G` и утверждённый PBIT. | Подтверждены feedback core, Jivo, три статуса и базовый funnel ID; остаются visit denominator и source rerun/SLA. Сверка с фактическими цифрами Power BI не входит в pre-creation gate по решению пользователя 2026-08-18. |
| Посещаемость клиентов с долгами | `SV-099`. | Подтверждены movement key и document branches; остаются stable visit classification, as-of сверка и SLA. |
| Карта администратора | `SV-100`, `AC-V05`. | Подтверждены event key, success и однозначный card→club; source-side технических gaps не осталось. |
| Маркетинговая воронка | `SV-101`, `MF-V04/V06/V07/V07C` и утверждённый PBIT. | Подтверждены task code в scope, join без размножения, наблюдение states, duration/payment type; остаются `MF-V08` и source rerun/SLA. Сверка с фактическими цифрами Power BI не входит в pre-creation gate по решению пользователя 2026-08-18. |
| Членство для правления | `SV-096` переиспользуется для единицы рекарринга. | Больше нет блокера «физический monthly payment key»; остаются states, non-additivity и SLA. Сверка итогов board-отчёта с Power BI возможна только при наличии фактических контрольных значений и не входит в pre-creation gate. |

## Актуальный остаток, который держит global gate

Ни один из пунктов ниже не требует нового бизнес-решения, пока сохраняется
первый релиз по текущим SQL/M/DAX и уже принятым правилам. Это технические
контроли или независимые сверки, которые должны быть выполнены и сохранены
перед отдельным полным review gate.

| Отчёт | Ровно что остаётся |
|---|---|
| Отчёт по поступлениям | states/sign, predecessor `MIN(ID)` и независимая сверка текущего отчёта. |
| Продажа детских пакетов | знак возврата и states источника. |
| Новички и гостевые визиты | physical control утверждённых 12 услуг, states, key/cardinality, 0/44/45 outcome и booking attribution. |
| Отчёт по обращениям | business grain знаменателя посещений, source rerun/SLA. |
| Посещаемость клиентов с долгами | stable visit classification, as-of control, SLA. |
| Работа с посещаемостью | daily client-base denominator и historical refresh SLA. |
| Маркетинговая воронка | `MF-V08` для полной меры накопленного трафика, source rerun/SLA. |
| Членство для правления | states, non-additive KPI и SLA. |

## Вывод

«Загрузка ОП» и «Карта администратора» исключены из перечня технических gaps.
Для остальных восьми отчётов выше уточнён и сокращён остаток; закрытые части не должны запускаться
повторно. Глобальный gate остаётся закрытым до выполнения всего перечисленного
и отдельной документарной проверки всех 31 договорных отчётов и 38 объектов.

Основания: [server validation](../source_metadata/server_validation_2026-08-14.md),
[checkpoint ledger](../../.agents/report_checkpoint_ledger.tsv),
[единый реестр](global_unresolved_questions_register_2026-08-14.md) и
[утверждённые PBIT-правила](../source_reports/pbit_old_index.md).
