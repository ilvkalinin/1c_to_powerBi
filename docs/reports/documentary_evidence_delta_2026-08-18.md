# Документарная сверка после global read-only review — 2026-08-18

Статус: `DOCUMENTARY_AUDIT_COMPLETE / NO_SOURCE_QUERIES_RUN`.

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
| Отчёт по обращениям | `SV-098`, `CR-V05D—G` и утверждённый PBIT. | Подтверждены feedback core, Jivo, три статуса и базовый funnel ID; остаются visit denominator, Power BI reconciliation и SLA/rerun. |
| Посещаемость клиентов с долгами | `SV-099`. | Подтверждены movement key и document branches; остаются stable visit classification, as-of сверка и SLA. |
| Карта администратора | `SV-100`, `AC-V05`. | Подтверждены event key, success и однозначный card→club; остаётся независимая дневная сверка с Power BI. |
| Маркетинговая воронка | `SV-101`, `MF-V04/V06/V07/V07C` и утверждённый PBIT. | Подтверждены task code в scope, join без размножения, наблюдение states, duration/payment type; остаются `MF-V08`, Power BI reconciliation и SLA/rerun. |
| Членство для правления | `SV-096` переиспользуется для единицы рекарринга. | Больше нет блокера «физический monthly payment key»; остаются states, board reconciliation, non-additivity и SLA. |

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
| Отчёт по обращениям | business grain знаменателя посещений, Power BI reconciliation, rerun/SLA. |
| Посещаемость клиентов с долгами | stable visit classification, as-of control, SLA. |
| Работа с посещаемостью | daily client-base denominator и historical refresh SLA. |
| Карта администратора | независимая дневная сверка с Power BI. |
| Маркетинговая воронка | `MF-V08` для полной меры накопленного трафика, Power BI reconciliation, rerun/SLA. |
| Членство для правления | states, board reconciliation, non-additive KPI и SLA. |

## Вывод

«Загрузка ОП» исключена из перечня технических gaps. Для остальных девяти
отчётов выше уточнён и сокращён остаток; закрытые части не должны запускаться
повторно. Глобальный gate остаётся закрытым до выполнения всего перечисленного
и отдельной документарной проверки всех 31 договорных отчётов и 38 объектов.

Основания: [server validation](../source_metadata/server_validation_2026-08-14.md),
[checkpoint ledger](../../.agents/report_checkpoint_ledger.tsv),
[единый реестр](global_unresolved_questions_register_2026-08-14.md) и
[утверждённые PBIT-правила](../source_reports/pbit_old_index.md).
