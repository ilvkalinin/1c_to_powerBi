# Единый Stage 2 пакет доказательств — 2026-08-14

Статус: `ACTIVE / READ ONLY ONLY`.

Пользователь 2026-08-14 разрешил один общий пакет для десяти
`TECHNICAL_GAP` из [сверки evidence](evidence_reconciliation_2026-08-14.md).
Разрешены только заранее определённые source-side проверки в
`REPEATABLE READ, READ ONLY` снимках. Запрещены DDL, DML, создание объектов,
изменение 1С, Power BI external Excel и изменение согласованных правил.

| Отчёт | Контроли | Ожидаемый результат |
|---|---|---|
| Загрузка ОП | SA-V02—V04 | bounded legacy filter завершается; phone/role/cardinality записаны без изменения правила. |
| Отчёт по поступлениям и Членство для правления | full movement key, states/sign, recurring key, board/non-additive reconciliation | физические ключи и current KPI единицы подтверждены либо расхождение сохранено. |
| Продажа детских пакетов | CP-V03—V06 | price/product, return sign, states, sentinel/card controls записаны. |
| Новички и гостевые визиты | V-02/V-05/V-06/V-09 | first-visit, ACCUNIQ, 0/44/45 outcome, booking attribution записаны. |
| Отчёт по обращениям | CR-V03 HTML, CR-V05—V11 | HTML/follow-up, topic/filter, denominator и SLA записаны. |
| Посещаемость клиентов с долгами | DV-V03—V07 | document/prebooking/text/as-of/state/SLA controls записаны. |
| Работа с посещаемостью | WA-V06, WA-V08 | daily client-base dependency и annual query/SLA измерены. |
| Карта администратора | Gymmy key/success/card→club/daily count | rule current cards/directions/count подтверждён. |
| Маркетинговая воронка | physical task-code/join/state | BR-020 воспроизводима на физическом источнике. |

Каждый отчёт завершается отдельным evidence artifact и только затем получает
свой commit/status. Даже успешное завершение всех строк не открывает Stage 3:
после пакета требуется полный audit и новое явное решение пользователя.
