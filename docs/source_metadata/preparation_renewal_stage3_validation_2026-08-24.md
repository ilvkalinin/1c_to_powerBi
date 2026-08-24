# Stage-3 source validation: «Подготовка к продлению»

Статус: `VALIDATED` для первого физического продукта
`mart.preparation_renewal_checkpoint`.

Все запросы выполнены на VM-1 в `REPEATABLE READ, READ ONLY`; source не
изменялся. Результаты относятся к live snapshots 2026-08-24, поэтому
численные totals будущей загрузки фиксируются заново в том же snapshot, что и
target COPY.

| Контроль | Ожидание | Факт | Статус |
|---|---|---|---|
| PR-V10 | Физические поля contract/visit/freeze существуют с ожидаемыми типами | 48 проверенных columns; ссылки — `bytea`, даты — `timestamp`, states — `boolean`/`numeric` | VALIDATED |
| PR-V11 | Legacy scope contracts не имеет пустых обязательных dimensions | 857 516 checkpoint rows; 0 orphan club/client, 0 zero-club, 0 blank code; 3 birth-date sentinel, 2 marked contract сохраняются без нового filter | VALIDATED |
| PR-V12 | current pair contract+client не размножает посещения | 496 089 visit rows = 496 089 physical keys; inactive/marked service rows = 0; окно 2024-12-03—2026-12-22 | VALIDATED |
| PR-V13 | Technical freeze predicate воспроизводит current DAX result | 857 516 checkpoints; legacy and technical flags по 59 793; difference = 0 | VALIDATED |
| PR-V14 | Нельзя упрощать freeze только по interval existence | direct simplified predicate дал 62 140 flags и 2 347 differences | REJECTED safeguard |
| PR-V15 | Периодный доступ к freeze source индексируем | июль 2026: 28 718 rows, index scan, 473,693 ms | VALIDATED |
| PR-V16 | Bounded extract и независимый M control завершаются | июль: extract 42 754 rows / 91 243 visits / 6 907 frozen / 28 255 below target; independent control точно совпал и после set-based rewrite занял 3,57 s | VALIDATED |

## Зафиксированные safeguards

- Посещения сохраняют exact current pair `AccumRg7575.contract_ref + client_ref`
  и current text filter `Reference163.Description = 'посещение клуба'`;
  `Active`, `Marked`, `Posted` и storno filters не добавляются.
- Заморозка формируется из legacy `AccumRg7478 → InfoRg5859`, выбирая latest
  movement по `(contract_code, freeze_start_date)`. В target применяется
  technical contract predicate только потому, что PR-V13 доказал его полную
  эквивалентность DAX-natural result на BR-003 horizon.
- Three `0001-01-01` birth dates produce `NULL` `age_group`, как допускает
  data contract; это не скрытая категория «Дети».
- Контрольный transport не является business reconciliation: перед каждым
  COPY отдельный legacy-M query фиксирует expected rows, visits, frozen и
  below-target totals.
