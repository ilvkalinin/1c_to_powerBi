# Incremental design: `client_base_snapshot_retention`

Статус: `INCREMENTAL_CANDIDATE / IMPLEMENTATION_NOT_EXECUTED`.

`mart.client_base_snapshot` и `mart.client_base_retention` составляют одну
неразделимую job: retention использует comparative baseline тех же client-base
снимков. Новый отдельный runner
`scripts/load_client_base_snapshot_retention_incremental.py` не вызывает
`run_once()` существующего full-rebuild loader и не имеет DDL path.

Изменения `AccumRg7575`, `InfoRg5654`, `AccumRg7646` и child tabular parts
нельзя надёжно выбрать watermark’ом. Вместо него применяется подтверждённое
контрактом правило: каждый запуск атомарно пересчитывает текущий и предыдущий
календарный месяц. Для retention extract сам добавляет требуемые comparative
baseline dates прошлого года. Строки за пределами окна сохраняются.

Runner экспортирует один `REPEATABLE READ, READ ONLY` snapshot, затем для
каждого `fact × month` создаёт один bounded aggregate-only COPY file и снимает
independent controls до COPY. После source stage одна target transaction
создаёт две temporary stages, проверяет keys/contracts/independent totals и
заменяет обе facts только внутри окна. Любая ошибка до `COMMIT` откатывает
target; full-loader не используется как fallback.

Fresh read-only August plans:

| Fact | Rows | Time | Notable I/O |
|---|---:|---:|---|
| snapshot | 99,515 | 20.770 s | 2,569,066 shared hit; 44,115 / 33,594 temp read/write blocks |
| retention | 64,905 | 32.956 s | 2,573,385 shared hit; 59,555 / 59,557 temp read/write blocks |

The two-month run is therefore incremental by replacement scope, but is not
advertised as a one-minute SLA. No DML, COPY, scheduler task or source change
was executed in this design package.
