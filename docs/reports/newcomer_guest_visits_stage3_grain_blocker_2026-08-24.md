# BLOCKER: воспроизводимый grain «Новички и гостевые визиты»

Статус: `DECISION_REQUIRED`.

В согласованном Stage 3 execution package повторены read-only diagnostics в
одном `REPEATABLE READ, READ ONLY` snapshot без вывода ПДн и raw IDs.

| Факт | Текущее правило | Наблюдаемый факт | Почему это блокирует DDL/reconciliation |
|---|---|---|---|
| `mart.new_first_visit` | `ROW_NUMBER(contract ORDER BY Period)` без второго порядка | В июле 2026: 35 контрактов, 70 строк на раннем timestamp; у 33 различаются клиент или клуб, у 35 — документ посещения | Grain «одна строка на контракт» требует выбора одной строки, но current rule его не задаёт. |
| `mart.guest_visit_conversion` | final `Distinct(client code, guest_visit_date)` | В июле 2026: 4 804 duplicate client-date groups, 9 766 строк; все группы различаются registration/status/time/recorder input | Grain «гость × дата» не позволяет хранить перечисленные detail-поля без правила выбора. |

Существующие BR-018/BR-031 запрещают агенту самостоятельно добавлять
tie-break или скрытую дедупликацию. Варианты, требующие явного решения:

1. выбрать детерминированный physical key 1С как второй порядок; grain остаётся
   `contract_id` и `client_code × guest_visit_date`, rerun становится
   проверяемым;
2. сохранять все равные строки; grain обеих facts меняется на техническую
   source-row детализацию, а Power BI продолжает legacy distinct/ranking;
3. оставить selection в Power BI; тогда две новые physical facts не могут
   считаться полной реализацией detail output.

До выбора разрешены только работы, не зависящие от этой селекции. DDL, DML и
reconciliation этих двух фактов fail-closed запрещены.
