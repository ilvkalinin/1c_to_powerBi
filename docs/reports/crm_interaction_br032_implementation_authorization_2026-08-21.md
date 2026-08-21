# CRM BR-032/BR-033 implementation authorization

Дата: 2026-08-21. Статус: `COMPLETED`.

Пользователь подтвердил единый Stage-3 пакет: выполнить
[`crm_br032_reviewed_plan.sql`](../../sql/marts/crm_br032_reviewed_plan.sql),
получить из одного read-only source snapshot четыре compact facts с
максимальным преобразованием на VM-1, выполнить atomic COPY, reconciliation,
rerun и измерение. Разрешено удалить только шесть ранее созданных пустых CRM
objects, перечисленных в reviewed plan. Не менять 1С, PBIT, schedules,
инкремент или guest outcomes BR-031. До commit любого failed DML — rollback;
после commit удаления/изменения не автоматизируются.

## Поквартальная передача `feedback` — performance correction

Статус: `CONFIRMED` для первоначальной загрузки текущего горизонта.

Изначально `feedback` выполнялся один раз на весь горизонт, хотя параметр
`--chunk-months` применялся к `core` и `phone`. Фактический `EXPLAIN ANALYZE`
на VM-1 для горизонта `2025-01-01`…`2026-08-21` вернул 154 741 строку за
25,542 с; read-only `COPY` в процесс загрузчика передал 150 963 092 байта за
70,188 с. Это не был однодневный запрос.

Перед добавлением границ чанка выполнен read-only контроль точного набора
полей финальной бизнес-группы `feedback`: 154 741 групп, пересекающих границу
квартала — 0. Поэтому разбиение по кварталу не меняет текущую группировку,
агрегаты комментариев или поиск первого последующего обращения.

`feedback` теперь принимает `$3/$4`, а загрузчик выполняет его в том же
поквартальном цикле, что `core` и `phone`. На VM-1 квартал
`2025-04-01`…`2025-07-01` дал 22 105 строк за 3,659 с без временных файлов;
read-only `COPY` в процесс загрузчика — 22 755 201 байт за 4,805 с. Все четыре
секции прошли штатный `--validate-source` на этом квартале. VM-2 не
изменялась при этих проверках.

Отдельный read-only set-based контроль сравнил старое `::text` и новое
индексируемое `::mvarchar` сопоставление для всех 138 454 `task_code` и
95 749 `client_code` текущего горизонта: разниц нет с обеих сторон. Поскольку
результат follow-up зависит только от `task_code × client_code × created_at`,
расчёт один раз для уникального ключа и последующий join сохраняют результат
исходного коррелированного выражения.

## `core` — ограничение текущего transport plan

Статус: `RESOLVED` решением пользователя 2026-08-21.

Для квартала `2025-04-01`…`2025-07-01` фактический read-only
`EXPLAIN ANALYZE` текущего `core` выполнялся 76,427 с. Внутри
`sales_candidates` он последовательно прочитал 17 158 191 строку
`_reference67`, сформировал 1 483 523 кандидата и только затем применил
`scoped_chunk`. Полный горизонт не завершился за установленный лимит 180 с и
был остановлен без VM-2 DML.

Причина — подтверждённое правило `anchor_at = min(phone_at, started_at)`:
границу квартала нельзя перенести во входной фильтр без изменения строк,
когда у одного обращения есть несколько phone events. В read-only 1С нет
индекса, поддерживающего это межтабличное вычисление. Поквартальный повтор
текущего `core`/`phone` будет повторять полный scan; безопасная смена стратегии
требует отдельного решения о новом staging/index/семантике.

Пользователь подтвердил транспортный `created_at`-predicate, ограниченный
измеренным окном и обязательным fail-closed guard; его реализация и результат
initial load зафиксированы ниже. Бизнес-дата `anchor_at` и телефонная
семантика не изменялись.

## Устойчивость подключений загрузчика

Статус: `CONFIRMED`.

Для каждого нового подключения к VM-1 и VM-2 `load_crm_br032.py` делает до
пяти попыток, запланированных с интервалом 15 секунд (0, 15, 30, 45 и 60 с).
Каждая попытка сохраняет `connect_timeout = 15` с, поэтому при недоступности
сервера исходная ошибка возвращается не позднее примерно 75 с. Повторяются
только ошибки открытия соединения; ошибки пароля, роли, базы и SQL не
маскируются повторными попытками. Read-only probe VM-1 после изменения вернул
`SELECT 1`; отдельный изолированный тест подтвердил пять попыток и четыре
паузы по 15 с. VM-2 и данные источника этой проверкой не изменялись.

## Окно `created_at` для transport quarter

Статус: `IMPLEMENTED` по явному решению пользователя 2026-08-21; текущий
source snapshot остаётся единственным доказательством выбранной границы.

Read-only diagnostic
[`crm_br032_quarter_created_window.sql`](../../sql/tests/crm_br032_quarter_created_window.sql)
в точности повторил membership и `min` transport-anchor из `CORE-001`, затем
сравнил его с `Reference67._Fld823` (`created_at`). Результаты:

| quarter of transport anchor | rows | maximum required lookback from quarter start | required lookahead after quarter end | rows outside quarter ±1 month |
|---|---:|---:|---:|---:|
| 2025-Q1 | 189 708 | 36 d 06:52:35 | none | 5 |
| 2025-Q2 | 163 252 | 71 d 00:00:00 | none | 5 |
| 2025-Q3 | 166 814 | 58 d 10:20:00 | none | 4 |
| 2025-Q4 | 281 244 | 53 d 07:04:54 | none | 10 |
| 2026-Q1 | 285 513 | 63 d 11:44:24 | one row at exactly 2026-04-01 00:00 | 8 |
| 2026-Q2 | 264 919 | 59 d 00:00:00 | none | 10 |
| 2026-Q3 to 2026-08-21 | 168 435 | 47 d 12:45:16 | none | 3 |

Therefore quarter ±1 month would omit 45 current interactions. For this exact
snapshot, the single conservative source predicate
`created_at >= chunk_start - interval '71 days'` and
`created_at < chunk_end + interval '1 day'` includes every current core row;
an exact quarter-only predicate would omit 4 943 rows. A read-only Q2 plan
probe with these bounds used `_reference67_7` and completed in 11.466 s,
versus 76.427 s for the current Q2 plan. This is plan time only, not an
end-to-end load SLA.

The 71-day bound is observed data, not a confirmed business limit: a later
interaction can still be entered with an older `created_at`. Therefore
`CORE-001` and `PHONE-001` now apply the tested source predicate, but the
loader first runs this full-horizon diagnostic in the exact exported
`REPEATABLE READ` snapshot. It aborts before the first source `COPY` and
before any VM-2 connection/DML when it finds `created_at IS NULL`, a lookback
greater than 71 days, or a lookahead of one day or more. Thus a future outlier
cannot become silent data loss.

Implementation controls passed: all five source SQL sections passed
`--validate-source`; the live guard accepted 1 519 891 current interaction
keys; modified Q2 `CORE-001` returned the unchanged 163 252 rows; and an
isolated 72-day breach test raised `CORE_CREATED_WINDOW_GUARD_FAILED`.

## Bounded VM-2 COPY retry

Статус: `IMPLEMENTED`.

The first post-change full run passed the source guard and prepared all source
files, but the target transfer stalled while copying a bounded `phone` quarter.
It was terminated before commit; read-only verification confirmed all three
pre-existing CRM replacement tables remained at zero rows. No partial target
data survived.

By user decision 2026-08-21, every target `COPY` is now limited to 300
seconds. A transient target
connection error or this timeout rolls back the entire target transaction and
retries it up to five times, 15 seconds apart, using the already prepared local
binary files rather than querying VM-1 again. An isolated test forced the first
target `COPY` to fail and verified one rollback followed by a successful second
atomic attempt. Non-network and reconciliation errors remain fail-closed and
are not retried.

## Commit and rerun acceptance

Статус: `VALIDATED`.

Initial atomic `--apply` committed in 809.235 s with source snapshot totals
`core=1 519 894`, `phone=1 002 750`, `feedback=154 741`, and
`club_day=8 590`. The required atomic `--rebuild` then committed in 827.380 s.
Its later read-only snapshot contained six additional current `core` rows and
reconciled exactly to VM-2: `core=1 519 900`, `phone=1 002 750`,
`feedback=154 741`, `club_day=8 590`.

Both commits passed source-to-target count equality, compact keys/duplicate
checks, required-core/null/flag controls and public-select control inside the
target transaction. Neither run required a target retry after the 300-second
per-COPY limit was introduced. The separate initial stalled pre-limit run was
terminated before commit and left the pre-existing empty targets unchanged.
