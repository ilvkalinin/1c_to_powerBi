# RM-ARCH-001: архитектурная переоценка «Управления продлением»

Статус: `RECOMMENDATION / CURRENT-STATE RELEASE CONFIRMED; HISTORY SNAPSHOT DECISION_REQUIRED`.

Дата: 2026-08-29.

## Вопрос

После измерения exact source extract пользователь запросил оценку трёх
вариантов: постоянные базовые таблицы VM-2 для договоров/посещений/взаимодействий,
повторное использование существующих mart VM-2 и способ обновления уже
завершившихся договоров.

## Наблюдаемые факты

| Объект / ветвь | Подтверждённый grain или scope | Вывод для этого продукта |
|---|---|---|
| Exact source extract №16 | один заканчивающийся исходный договор | Полный `EXPLAIN (ANALYZE, BUFFERS)` вернул 240 969 строк за 89.433 s. Это измеренный baseline полного compact rebuild, не обоснование для реплики source-регистров. |
| `mart.visit_client_day` | дата посещения × фактический клуб × обезличенный клиент | Нет `contract_id`. Нельзя получить current-M `visit_count` по договору без новой, недоказанной атрибуции посещения к договору. Не использовать. |
| `mart.membership_contract_kpi_unit` | договор предоплаты либо ежемесячная KPI-единица рекарринга | Это не один membership contract; возможны KPI-месяцы и отсутствуют необходимые неплатные кандидаты. Не использовать для next-contract. |
| `mart.contract_usage` | frozen `%Renew` contract domain | Его scope и renewal-семантика уже признаны несовместимыми с №16. Не использовать. |
| `mart.crm_interaction` | одно `Reference67.ID`, но только объединённый sales/guest scope, с фильтрами funnel/employee/time | Текущий №16 отбирает `task type = «Продажа клубной карты»`, исключает planned/auto и выбирает latest по клиенту. Эквивалентность наборов не доказана; core может не содержать подходящие строки. Не использовать без отдельного mapping, full-population equivalence-control и измерения. |

Постоянное копирование `Reference59`, `AccumRg7575`, `Reference67` или
информационных регистров на VM-2 нарушит BR-001: это будет новая сырая
реплика со своим refresh, correction/deletion handling и риском расходящейся
семантики. Оно не уменьшает число бизнес-решений, а переносит их в несколько
несогласованных мест.

## Семантика уже спроектированного current-state факта

`mart.renewal_management_contract` имеет одну строку на исходный договор и
полностью заменяется атомарно при refresh. Это reproduces проверенный current
Power BI pattern; оно **не является историческим снимком**.

| Поле | Что происходит при следующем refresh | Пример для договора, завершившегося в 2025 или начале 2026 |
|---|---|---|
| `next_contract_*`, Renew-флаги | Повторно выбирается самый ранний на известную сейчас дату начала подходящий договор того же клиента. При tie применяется BR-050: платный, затем min technical ID. | Если позднее появился подходящий договор, ранее пустой next-contract станет заполненным; флаги и lag могут измениться. |
| `last_interaction_*`, funnel, fail reason | Повторно выбирается последнее на момент refresh допустимое взаимодействие; при равном timestamp — min technical ID по BR-050. | Новое обращение в 2026 заменит последнее взаимодействие для договора 2025 года. |
| `current_rating`, `current_tenure` | Берётся последняя доступная на refresh строка соответствующего info register. | Стаж/рейтинг будет текущим, а не тем, который был на дату окончания договора. |

Это поведение прямо зафиксировано в текущих mapping и ADR-0007. Полный rebuild
правильно отражает corrections, deletions и поздние сделки, но намеренно не
«замораживает» прошлое.

## Рекомендация

Для первого выпуска сохранить одну компактную физическую таблицу
`mart.renewal_management_contract` и source-side derived extract. Не создавать
на VM-2 самостоятельные базовые копии visits/contracts/interactions и не
перестраивать текущий admission в несколько core-таблиц. Измеренные 89.433 s
относятся к source extract; повторное использование допускается только после
доказательства одинаковых grain, scope и filters, а на сегодня такого
доказательства нет.

Если бизнесу требуется ответ «что было известно именно на дату окончания»,
это второй продукт, а не изменение смысла current fact:

`mart.renewal_management_contract_snapshot`

- grain: исходный договор × `as_of_date`/согласованная контрольная точка;
- обязательны `as_of_date`, snapshot policy, retention и отдельные поля
  `as_of_next_contract_*`, `as_of_last_interaction_*`, `as_of_rating`,
  `as_of_tenure`;
- кандидаты next-contract и interaction должны быть ограничены знанием на
  эту контрольную дату, а не текущим состоянием;
- строка, уже закрытая в 2025 году, не станет исторически достоверной задним
  числом только из текущей таблицы. Нужны либо сохранённые snapshots, либо
  отдельное подтверждение, что source history позволяет воспроизвести каждое
  поле as-of; это пока `VALIDATION_PENDING`.

Смешивать current и as-of атрибуты в одной строке нельзя: пользователь Power
BI не сможет отличить изменяющееся current outcome от зафиксированного
исторического результата.

## Последствие для текущего Stage 3 пакета

Рекомендация не меняет approved current-state SQL, DDL или BR-050. Новый
snapshot-product либо любая замена source extract на существующий mart имеет
другие grain/semantics и потребует отдельного mapping, measured plan и
immutable Stage-3 admission. До такого решения разрешённый current-state
пакет не расширяется.

## Связанные артефакты

- [ADR-0007](../adr/0007-renewal-management-current-state.md)
- [data contract](../data_contracts/renewal_management.md)
- [mapping](../mappings/renewal_management.md)
- [Stage 3 technical scope](renewal_management_stage3_technical_scope_2026-08-29.md)
- [data product catalog](../catalogs/data_products.md)
