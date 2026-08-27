# Авторизация: полный аудит будущих дат в физических витринах

- Дата: 2026-08-27
- Пакет: `project_future_date_compliance_2026-08-27`
- Этап: `STAGE_3_PRODUCT_ADMISSION`
- Отчёт: `project_future_date_audit`
- Основание: пользователь подтвердил предложенный самостоятельный пакет после
  успешного закрытия `client_base_snapshot_retention`.

## Scope и границы

Проверить все physical base tables схемы `mart`, имеющие business-date либо
business-timestamp колонку, на строки позднее текущей московской даты. До
полного сканирования собрать catalog inventory и выполнить безопасный
репрезентативный `EXPLAIN (ANALYZE, BUFFERS)` точного read-control. Для каждой
подтверждённой строки зафиксировать relation, date-column, count, min/max и
независимый контрольный запрос.

Если future rows найдены, в scope разрешены только: rollback-only месячный
DELETE probe на точной relation/column, затем один atomic target cleanup ровно
этих подтверждённых строк и post-cleanup reconciliation. Запрещены DDL,
изменения 1С, Power BI, источников, grain и методики. Таблицы без business-date
колонки фиксируются как `NOT_APPLICABLE`, не как PASS.

## Критерий закрытия

Catalog inventory complete; every applicable fact has reproducible control;
all confirmed future-row counts after any required cleanup are zero; read-plan
and any cleanup probe are measured; documentation, ledger and commit completed.
