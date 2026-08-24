# Авторизация: минимальные date-facts «Новички и гостевые визиты»

Статус: `EXECUTED AND VALIDATED`.

Дата: 2026-08-24.

## Подтверждённое пользователем правило

- Для первого посещения важен факт квалифицированного посещения по договору;
  при равных строках не выбираются клиент или документ.
- Для гостевого визита важна дата визита; не выбираются документ регистрации,
  статус, время или recorder.

## Scope полного автономного пакета

- `mart.new_first_visit`: ровно одна строка на `contract_id`; поля
  `contract_id`, `first_visit_date`. Дата — минимум `Period::date` среди
  current-PBI qualifying movements договора в горизонте BR-003.
- `mart.guest_visit_conversion`: ровно одна строка на
  `client_id × guest_visit_date`; поля `client_id`, `client_code`,
  `guest_visit_date`, `accuniq_same_day_flag`,
  `purchase_activation_date`, `purchase_lag_days`. Исходные регистрации
  сначала сводятся к устойчивой паре клиента и даты; contract/document/status
  не выбираются в detail.
- Полный read-only source review, immutable source SQL, target DDL, grants,
  atomic full BR-003 rebuild, source-to-target reconciliation, rerun и
  measured performance review.
- Все новые Python runners используют общую policy: первая попытка плюс ровно
  пять повторов только для `psycopg.OperationalError`.

## Граница

Не меняются 1С, current Power BI/PBIT и его M/DAX, внешние файлы, клубная и
демографическая detail, а также инкрементальная загрузка. Клуб не будет
перенесён без устойчивого source-rule; его divergence при ties измеряется
read-only и документируется. В VM-2 не копируются raw-регистры.

## Операции и rollback

Создаются ровно две таблицы `mart.new_first_visit` и
`mart.guest_visit_conversion`, их PK/только доказанные индексы и grants.
Загрузчик делает source-side compact extract во временные CSV, затем в одной
целевой транзакции берёт advisory lock, очищает две таблицы, выполняет COPY и
commit; при ошибке выполняется rollback. Автоматического удаления объектов
нет; rollback объекта — отдельный `DROP TABLE` только по явному решению.

Reviewed immutable SQL:

- [`DDL`](../../sql/marts/newcomer_guest_visits_minimal_date_facts_ddl.sql);
- [`source extracts`](../../sql/marts/newcomer_guest_visits_minimal_date_facts_extract.sql);
- [`reconciliation`](../../sql/tests/newcomer_guest_visits_minimal_date_facts_reconciliation.sql);
- [`atomic loader`](../../scripts/load_newcomer_guest_visits_minimal_date_facts.py).

## Критерий закрытия

Зафиксированные до DDL control values для обеих facts совпадают с target без
отклонений; PK, required-null, horizon, set comparison и rerun passed. В
одном повторном прогоне сохраняются те же row counts/keys/dates. Производительность
измерена на фактическом full rebuild без заявления об incremental SLA.
