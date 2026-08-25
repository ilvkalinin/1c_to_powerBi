# Playbook: обязательный preflight поставки физической витрины

Применяется к каждому новому Stage-3 пакету, который создаёт или перезагружает
физическую витрину на VM-2. Дополняет, но не отменяет `stage_3.md`, `safety.md`
и skills mapping/data-quality/performance. Не открывает Stage 3 сам по себе.

## Цель

Получить один воспроизводимый target-fact без raw-реплики 1С, без зависания
длинного межсерверного портала, с доказуемым source-to-target reconciliation и
без частичного состояния на VM-2.

## До согласования пакета

В артефакте admission до пользовательского approval зафиксируй неизменяемые
ссылки на reviewed `mapping`, `ADR`, `DDL`, source extract, loader и
reconciliation SQL. Назови все target-объекты, DDL/DML, rollback, способ
транспортировки, expected controls, показатели производительности и критерий
закрытия.

Не допускается колонка в DDL/extract, если для неё нет подтверждённых source,
преобразования, PostgreSQL-типа, NULL-policy, grain, evidence и теста.
`UNKNOWN` допустим только вне реализуемого SQL; не прятать его в заголовке
«validated». До DDL должны быть закрыты grain, логический ключ, cardinality
рискованных JOIN, source states (deletion/active/posted/correction) на полном
горизонте загрузки и смысл технических кодов, поступающих в contract.

## Соединения, источники и транспорт

1. До любого full-range `EXPLAIN`, `COPY`, DDL/DML или transport выполнить
   `EXPLAIN (ANALYZE, BUFFERS)` точного source extract на репрезентативной
   ограниченной выборке. Записать границы, rows, execution time и I/O, оценить
   масштабирование и не выполнять параллельно тяжёлый plan/transport. Только
   после этого разрешён full-range baseline; target read-plan снимается после
   successful atomic load до acceptance.
2. Все runner'ы используют общую `connect_with_retry`: первая попытка и ровно
   пять повторов только при `OperationalError`; остальные ошибки не ретраятся
   бесконечно. Логируются endpoint, номер попытки, итоговая ошибка и время.
3. На VM-1 открыть один `REPEATABLE READ, READ ONLY` snapshot. Ограничить
   период и колонки в source SQL; выполнить фильтрацию и агрегацию на VM-1.
   Нельзя создавать raw/staging-реплику регистров на VM-2.
4. Не держать один многогигабайтный psycopg portal, пока открыты оба сервера.
   Передавать measured batch (обычно месяц) через один временный binary
   COPY-файл: source COPY завершается, затем file COPY на VM-2, затем файл
   удаляется до следующей порции. В логе обязательны границы batch, строки и
   байты; перед запуском проверяется достаточное место для одной порции.
5. Временный файл — транспортный буфер, а не второй persistent dataset:
   одновременно разрешена только текущая порция; raw и client-level details
   не сохраняются. Если безопасный bounded transport невозможен, это
   `BLOCKER`, а не повод создавать вторую полную копию.
6. Изменять session-local planner setting разрешено только после сохранённого
   `EXPLAIN (ANALYZE, BUFFERS)` того же запроса и сравнения до/после. Не менять
   параметры или индексы 1С ради предположения.

## Target-загрузка и rollback

1. Initial DDL и load идут в одной target-транзакции. Rebuild существующей
   изолированной таблицы — в одной target-транзакции под transaction-scoped
   advisory lock.
2. `TRUNCATE + COPY` разрешён вместо `DELETE` только если измерены
   блокировка/время, таблица не разделяется с другим refresh, а rollback
   возвращает старое содержимое до commit. Иначе сохранить отдельную
   обоснованную стратегию swap/staging в ADR.
3. До commit target не должен показывать частичный snapshot. Ошибка в source
   COPY, target COPY или любом control вызывает rollback target и source.
   Автоматический `DROP` объекта запрещён.

## Независимая reconciliation и приёмка

1. До target COPY получить и записать expected controls в том же source
   snapshot, но отдельным reviewed source query/path, не тем же extract или
   join/formula, который проверяется. Как минимум: target-grain rows,
   business rows/documents, суммы, min/max date и точные фильтры/единицы.
   Это компактный scan без переноса raw-строк; его стоимость не заменяет
   transport control.
2. После COPY проверить минимум: source-to-target totals, key uniqueness,
   NULL/type/range contract, join multiplication/orphans, horizon/future
   dates, states/corrections/deletions и access boundary. Для каждого control
   записать ID, snapshot, executed_at, expected, actual, tolerance, источник
   независимого expected и difference.
3. Выполнить atomic rerun. При изменении live source между independent
   snapshots каждый прогон сверяется только со своими expected controls;
   разница между прогонами не объявляется ошибкой без target deviation.
4. До статуса `VALIDATED` измерить source plan, target read-plan и размер,
   initial/full-rebuild time и результат rerun. Full rebuild никогда не
   выдавать за incremental SLA. Инкрементальный SLA возможен только после
   отдельного доказательства watermark, late changes и deletions.
5. Power BI не изменяется в этом пакете, если действует BR-036. Contract в
   таком случае помечает Power BI connection/relationships как `DESIGNED` или
   `VALIDATION_PENDING`, а не как выполненную интеграцию.

## Checklist admission

Перед запуском отметь все пункты в admission evidence:

- [ ] Immutable reviewed set и перечень опасных операций показаны до approval.
- [ ] Все SQL-колонки полностью mapped; нет скрытых `UNKNOWN`.
- [ ] Grain/key/JOIN/states проверены на полном горизонте.
- [ ] Sample actual plan измерен до full-range plan/transport; масштабирование
      и отсутствие параллельного тяжёлого запроса зафиксированы.
- [ ] Source/target endpoints применяют initial + five retry policy.
- [ ] Snapshot, bounded batch, temporary-file cap и cleanup определены.
- [ ] Target transaction, lock, rollback и rebuild strategy измерены.
- [ ] Independent expected controls определены до COPY.
- [ ] Reconciliation, rerun, source/target performance evidence и Power BI
      boundary включены в критерий закрытия.
