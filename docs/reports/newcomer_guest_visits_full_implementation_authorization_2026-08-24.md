# Авторизация полного исполнения: «Новички и гостевые визиты»

Статус: `SUPERSEDED by minimal date-facts authorization 2026-08-24`.

Дата согласования: 2026-08-24.

## Решение пользователя

Пользователь разрешил довести до завершённой приёмки витрины
`mart.new_first_visit` и `mart.guest_visit_conversion` без промежуточных
согласований. Остановка допустима только при критическом вопросе, который
нельзя разрешить из подтверждённых SQL/M/DAX, mapping, business rules и
source evidence.

## Scope

- reuse review, фиксированный source-to-target mapping, grain, Power BI
  contract и minimal physical design для ровно двух facts;
- reviewed source extract, DDL, rollback, atomic initial load, target grants,
  source-to-target reconciliation, rerun и measured performance review;
- только read-only обращения к 1С и только объекты VM-2, перечисленные в
  reviewed implementation plan;
- единое operational hardening всех `scripts/load_*.py` и
  `scripts/refresh_*.py`: первая попытка соединения плюс ровно пять
  ограниченных повторов при `psycopg.OperationalError`, с наблюдаемой
  телеметрией и статической проверкой покрытия. Ошибки SQL, ролей и данных не
  повторяются и остаются fail-closed.

## Граница

Не включены новые business rules, изменения 1С, Power BI switch, внешние
Excel/Power Query, incremental refresh, новые продукты вне двух facts и
необоснованные индексы. Для уже существующих витрин меняется только механизм
повторного подключения; их данные не перезагружаются этим пакетом.

## Критерий закрытия

Обе витрины имеют immutable reviewed implementation plan, committed initial
load и atomic rerun. Все заранее записанные source-to-target controls имеют
нулевые отклонения; целевой grain/key/null/access/date controls и повторный
прогон passed. Каждый production loader проходит статическую проверку
connection-retry policy; все исключения доказательно перечислены.

## Изменение границы по критическому решению

При read-only Stage 3 diagnostic обнаружилось, что две требуемые facts не
имеют воспроизводимого one-row selection в current Power BI. Пользователь
2026-08-24 выбрал «оставить как в Power BI». Это отменяет только физическое
создание `mart.new_first_visit` и `mart.guest_visit_conversion` в данном
пакете; не является успешной initial load этих объектов и не разрешает
подменить их таблицами иной гранулярности. Выбор закреплён BR-035 и
[`stage-3 grain blocker`](newcomer_guest_visits_stage3_grain_blocker_2026-08-24.md).

Критерий закрытия пакета в этой части: source evidence и граница Power BI
documented; DDL/DML/reconciliation двух исключённых facts не выполняются.
Connection-retry hardening закрыт отдельно с полной проверкой покрытия.
