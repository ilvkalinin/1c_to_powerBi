# Авторизация Stage-2 server validation: «Воронка лиды фитнес»

Статус: `CONFIRMED`.

24.08.2026 пользователь явно подтвердил самостоятельный пакет
`STAGE_2_SERVER_VALIDATION / fitness_leads_funnel` после доказательного
Stage-3 planning blocker.

## Разрешённый scope

- только read-only source validation в одном `REPEATABLE READ, READ ONLY`
  snapshot 1С;
- V-01—V-09 и V-11 из
  `docs/reports/fitness_leads_funnel_query_review.md` для четырёх воронок и
  горизонта BR-003;
- подтверждение physical metadata, ключей, NULL, cardinality, source states,
  client-code attribution, service fallback, включающих 45-day boundaries и
  source control values;
- сохранить SQL, snapshot/watermark, expected result, actual result и
  reproducible discrepancy samples; обновить mapping и planning evidence.

## До исполнения: expected results

| Контроль | Ожидаемый результат |
|---|---|
| V-01 | Используемые объекты и поля существуют единственно; типы и 1С technical flags зафиксированы. |
| V-02 | `Reference106.ID` не имеет дублей; уникальность task code проверяется независимо. |
| V-03 | Четыре физические воронки и BR-003 task horizon дают воспроизводимые raw counts; исключение двух duplicate reasons фиксируется отдельно. |
| V-04 | Каждый task dimension join сохраняет одну строку на `task_id`. |
| V-05 | Current close-date/client-code service join не имеет скрытого размножения; иначе многозначность и DAX `MIN` фиксируются без смены правила. |
| V-06 | Ветки booking documents и VT4352 не создают незафиксированного размножения. |
| V-07 | Для task, booking и DPFU источников зарегистрированы фактические `Marked`, `Active`, `Posted`, cancellation/deletion states и их соответствие current filters. |
| V-08 | Client code проверен на NULL/дубли и на physical representability в task, booking и DPFU paths. |
| V-09 | Проверены включающие 45-day границы, closed-before-created, leap-day и earliest-booking-date ties; current DAX остаётся правилом BR-018. |
| V-11 | Source task, stage-booking, positive-training и training-sum controls рассчитаны с теми же BR-003 filters; сверка с Power BI возможна только при independently confirmed display controls. |

## Исключения

Пакет не разрешает DDL/DML, создание объектов, доступ к VM-2/mart, изменение
1С, Power BI/M/DAX/PBIT, Excel, Stage-3 plan, schedule или incremental
design. Наблюдаемое расхождение сохраняет current result по BR-018 и является
evidence/blocker, а не разрешением изменить логику.

Критерий закрытия: все доступные V-01—V-09/V-11 имеют сохранённый результат и
evidence; mapping либо становится fixed для будущего runnable admission, либо
содержит точный нерешённый physical blocker.
