# S3-RR-LOAD-001: первичная загрузка «Выручки рецепции»

Дата согласования: 2026-08-20. Статус: `COMPLETED / VALIDATED`.

Пользователь подтвердил полный пакет initial load после предложения сохранить
единый общий факт и не создавать вторую витрину.

## Scope

1. Воспроизвести confirmed current-M ветви `AccumRg7575` и `AccumRg7646` за
   BR-003: текущие типы номенклатуры, исключения членства/фитнеса и
   report-level исключения, ненулевая выручка, текущий сотрудник строки.
2. Назначить восемь current-M категорий в прежнем порядке из
   `docs/source_reports/reception_revenue/Выручка рецепции2.txt`;
   `revenue_scope = 'reception'`. Новую методику продавца, ID-категорий или
   источники не вводить.
3. В одной target-транзакции загрузить validated temporary stage в существующий
   `mart.ancillary_revenue_movement`, заменяя только `revenue_scope =
   'reception'`; все строки `dpfu` и view ДПФУ сохраняются неизменными.
4. Выполнить source/stage/target controls по ветвям, категориям, количеству и
   суммам, technical-key и scope-collision checks, contract/date controls,
   DPFU-preservation, view-read measurement и rerun.

## Граница, операции и rollback

Разрешён только DML в существующем `mart.ancillary_revenue_movement` и
existing view `mart.v_reception_revenue` читается без изменения. DDL, Power BI,
Excel, 1С, новая витрина и изменение `dpfu` scope исключены. До commit —
`ROLLBACK`; при любой ошибке прежние рецепционные строки остаются доступны,
а ДПФУ не затрагивается.

## Критерий закрытия

Source, stage и target совпадают по двум ветвям и всем восьми категориям;
нет duplicate/cross-scope technical keys, нарушений контракта или строк вне
BR-003; контроль до/после доказывает сохранность DPFU; rerun проходит, а
измеренная загрузка и чтение view зафиксированы.

## Фактический результат 2026-08-20

В source snapshot и target совпали 150 752 движения, 474 023,000 количества и
46 552 824,44 выручки; представлены все восемь категорий (девять сочетаний
`source_kind × category`). `duplicate_keys`, contract violations и
cross-scope collisions равны нулю. DPFU до и после обоих коммитов сохранён:
508 574 строки, 645 075 658,27. Первый refresh занял 74,20 с, rerun — 82,21 с.
Полное чтение `mart.v_reception_revenue` вернуло 150 752 строки за 415,186 мс.

Для S3-RGS-REUSE-005 fresh source control обнаружил один новый ключ на 245,00;
тот же approved loader обновил scope до 150 753 строк и 46 553 069,44 за
65,70 с. DPFU-preservation вновь прошёл.
