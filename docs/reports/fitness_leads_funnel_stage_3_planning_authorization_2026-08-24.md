# Авторизация Stage-3 planning: «Воронка лиды фитнес»

Статус: `CONFIRMED`.

24.08.2026 пользователь подтвердил самостоятельный planning-only пакет
Stage 3 для «Воронки лиды фитнес».

## Разрешённый scope

- выполнить reuse-review созданного `mart.marketing_funnel_task` только по
  grain и текущим подтверждённым правилам;
- зафиксировать source-to-target mapping для task core и отдельно обозначить
  task-outcomes, не смешивая их с task grain;
- подготовить минимальный mart-design, Power BI contract и точный будущий
  admission plan либо документированный `BLOCKER`.

Пакет не разрешает DDL/DML, подключение к 1С/VM, изменение Power BI/M/DAX,
Excel, планов, расписания или incremental refresh. Будущая реализация требует
отдельного явного runnable admission после reviewed SQL, controls и rollback.

Критерий закрытия: reviewed plan с fixed mapping/grain либо evidence-based
blocker, оформленный в документации.
