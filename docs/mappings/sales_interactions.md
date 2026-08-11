# Source-to-target mapping: взаимодействия отдела продаж

Статус: `BUSINESS MAPPING COMPLETE / TECHNICAL VALIDATION PARTIALLY VALIDATED — SV-084; Stage 3 deferred`.

Mapping основан на текущих SQL/M/DAX, metadata и решениях пользователя 2026-07-24. Общий core `mart.crm_interaction` и view `mart.v_sales_interaction` спроектированы в ADR-0016; DDL и реализация отложены до технической проверки.

## Stage 2 evidence — SV-084

На live `gymdb` в `READ ONLY` транзакции SA-V01 подтвердил 5 из 5 центральных
physical relations: `_reference67`, `_reference106`, `_inforg7146`,
`_inforg6291`, `_reference225`. Валидации SV-026—SV-034 остаются применимым
evidence для phone-row grain, join cardinality и current filters. SA-V02—SA-V04
сохранены с ожидаемым результатом, но не выполнены: полный bounded legacy path
достиг `statement_timeout`, а повторное соединение получило `ETIMEDOUT`.
Состояния и архивные признаки, full-population controls и независимые business
control values остаются `VALIDATION_PENDING`; Stage 3 не начинается.

## Подтверждённая гранулярность

Одна строка на самостоятельный звонок из `InfoRg7146`; если у
взаимодействия нет строки звонка — одна строка на `Reference67.ID`.
Взаимодействие с двумя звонками даёт две строки. Это подтверждённое
пользователем правило текущего отчёта и проверкой SV-026; нормализация звонков
в одну строку запрещена.

Логический ключ — составной: `interaction_id` + ключ строки `InfoRg7146`
(`Fld7147RRef`, `Fld8699`) для звонка; для interaction без звонка —
`interaction_id` + технический признак «нет звонка».

## Предварительные целевые поля

| Целевая колонка | Бизнес-описание | Источник / преобразование | Тип PostgreSQL | NULL | Статус | Проверка до SQL |
|---|---|---|---|---|---|---|
| `interaction_id` | стабильный ключ взаимодействия | `Reference67.ID` | UNKNOWN | нет | CONFIRMED source | уникальность после joins |
| `task_id` | владелец/задание воронки | `Reference67.OwnerID = Reference106.ID` | UNKNOWN | нет | CONFIRMED current | orphan rows |
| `interaction_date` | дата фактического взаимодействия | сохранить текущий `COALESCE(InfoRg7146.Fld7150, Reference67.Fld820)` после нормализации phone rows | `date` | нет | CONFIRMED current / technical validation | несколько phone rows и timezone |
| `created_at` | дата создания задачи | `Reference67.Fld823` | UNKNOWN | нет | CONFIRMED source | фактический тип |
| `planned_date` | плановая дата | `Reference67.Fld822::date` | `date` | да | CONFIRMED source | границы периода |
| `duration_seconds` | длительность для средней и медианы | разница `Reference67.Fld821 − Fld820`; `NULL`, если начало `00:00`, разница отрицательна или отсутствует | `integer` | да | CONFIRMED — current measure | midnight, outliers |
| `answered_flag` | ответ для текущей воронки звонков | `InfoRg7146.Fld7148` заполнен, но для входящего звонка принудительно `false` | `boolean` | нет | CONFIRMED — current measure | multiple phone rows |
| `event_type_id` | стабильный вид события | `Reference67.Fld831` | UNKNOWN | да | CONFIRMED source | перечень значений |
| `event_type_name` | русская категория события | mapping текущих 15 GUID; для прочих ID — `NULL`, как в текущем SQL | `text`/малый код | да | CONFIRMED current / SV-034 | не добавлять значение для `a11c516fb5884f2048dcdf57fd20462b` без отдельного бизнес-правила |
| `interaction_state_id` | состояние | `Reference67.Fld829`; ключ `Запланировано` = `99a9ebb169a4e2a611eeb5e55b05d103`, `В процессе` = `99a9ebb169a4e2a611eeb5e55b05d101` | `bytea` → protected/text key | да | CONFIRMED current / SV-033 | плановая страница фильтрует по ключу `Запланировано` |
| `interaction_state_name` | состояние для визуала | `Reference224.Description`; звонки `В процессе → Закрыто` по текущему DAX | `text`/малый код | да | CONFIRMED current / SV-033 | не использовать для фильтра плановой страницы |
| `interaction_status_id` | статус | `Reference67.Fld830` | UNKNOWN | да | CONFIRMED source | перечень значений |
| `interaction_status_name` | выполнено / не выполнено / отменено | mapping текущих GUID | `text`/малый код | да | current mapping | неизвестные статусы |
| `manager_id` | стабильный оператор | `Reference67.Fld824` | `bytea` → protected/text key | да | CONFIRMED source / physical join VALIDATED (SV-027) | 16.41% строк 2026 без совпавшего сотрудника; `LEFT JOIN` |
| `manager_name` | имя оператора | `Reference225.Description` | `text` | да | CONFIRMED need / physical join VALIDATED (SV-027) | не использовать как ключ; `LEFT JOIN` |
| `operator_club_id` | клуб задания | `Reference106.Fld1195`; текущий M не сверяет его с кадровой записью | `bytea` → protected/text key | да | CONFIRMED current | не добавлять кадровое условие по клубу: это изменит текущий отчёт |
| `network_name` | Физкульт / Пушкинский | по подтверждённому клубу | `text`/малый код | нет | current rule | справочник клубов |
| `client_key` | стабильный клиент | `Reference106.Fld1196` | UNKNOWN | да | CONFIRMED source | считать ли строки без клиента |
| `client_code` | код клиента | `Reference141X1.Code` | `text` | да | CONFIRMED need | доступ |
| `client_name` | ФИО в детальной таблице | `Reference141X1.Description` | `text` | да | CONFIRMED need | PII access |
| `client_phone` | телефон в детальной таблице | `Reference141X1.Fld1531` | `text` | да | CONFIRMED need | PII access |
| `tenure_type` | New / Ex / Renew | `Reference106.Fld1190` + текущий GUID mapping | `text`/малый код | да | CONFIRMED current | неизвестные значения |
| `client_status` | действительный / бывший / потенциальный | `Reference106.Fld1204` + текущий GUID mapping | `text`/малый код | да | CONFIRMED current | неизвестные значения |
| `funnel_id` | стабильная воронка | `Reference106.Fld1191`; разрешённый набор: `99a9ebb169a4e2a611eecbf18a73ffa6`, `99b0e03a7af94bc911ef0167b7844d74`, `99b0e03a7af94bc911ef016b69a7124a` | `bytea` → protected/text key | нет | CONFIRMED current / SV-030 | при реализации сравнить с текущим текстовым отбором |
| `funnel_name` | вид воронки | `Reference89.Description` | `text` | нет | CONFIRMED need | текущие три значения |
| `campaign_id` | маркетинговая кампания | `Reference106.Fld1197`; для исключения Jivo: `99e886b88886661011f0ae4e3da6296e`, `99cc8098b8acd0e411efe53f048393c3` | `bytea` → protected/text key | да | CONFIRMED current / SV-031 | исключать только вместе с сервисной воронкой |
| `campaign_name` | название кампании | `Reference145.Description` | `text` | да | current need | не использовать как filter key |
| `channel_id` | канал | `Reference106.Fld1194` | UNKNOWN | да | CONFIRMED source | фактическое использование |
| `cancellation_reason` | причина отмены | `Reference67.Fld828 → Reference202.Description` | `text` | да | current source | используется ли визуалом |
| `interaction_count` | вклад строки в количество задач | `1`, если код/ключ клиента непустой, иначе `0` | `smallint` | нет | CONFIRMED — current measure | null client reconciliation |

## Отбор сотрудников

Текущий M оставляет должности:

- `Менеджер ОП`;
- `Старший менеджер ОП`.

Интервал `InfoRg6291.Fld6298..Fld6299` проверяется на `Reference67.Fld823` (`ДатаСоздания`) — CONFIRMED.

Текущий M связывает `Менеджер` с кадровыми настройками по имени сотрудника,
после чего проверяет `ДатаПриема <= ДатаСоздания <= ДатаУвольнения` (верхняя
граница включительна; sentinel увольнения заменён на `2099-12-31`). Это
сохранённое правило первого релиза. SV-032 на январе 2026 подтвердил: `EXISTS`
с теми же условиями даёт ровно текущий результат `Table.Distinct` (98 798
строк), устраняя только размножение одной interaction кадровыми строками и
не удаляя самостоятельные звонки. Поэтому реализация использует `EXISTS`, а
не прямой join или `Table.Distinct`. Смена связи с имени на ID сотрудника —
методологическое улучшение и не входит в воспроизведение без отдельной сверки
результата.

## Отбор воронок

Текущая реализация оставляет:

- `Продажа клубной карты` — `99a9ebb169a4e2a611eecbf18a73ffa6`;
- `Сервисная воронка ОП` — `99b0e03a7af94bc911ef0167b7844d74`;
- `Корпоративная продажа` — `99b0e03a7af94bc911ef016b69a7124a`.

Из сервисной воронки исключаются кампании:

- `Заявка c Jivo-site Физкульт` — `99e886b88886661011f0ae4e3da6296e`;
- `Заявка с Jivo-site (Пушкинский)` — `99cc8098b8acd0e411efe53f048393c3`.

Пользователь подтвердил оставить этот охват без изменений. Отбор следует выполнять по стабильным ID/кодам.

## Одна таблица для двух страниц

Не создавать отдельный целевой факт `ЗапланированныеВзаимодействия`. Общая строка содержит обе даты и текущее состояние.

- основная страница фильтруется по `interaction_date`;
- страница планов — по `planned_date` и состоянию `Запланировано`;
- просрочка вычисляется относительно текущей даты: `planned_date < current_date`;
- исторические снимки backlog не создаются.

Способ двух календарных связей Power BI определяется после утверждения контракта.

## Граница PostgreSQL / Power BI

Два Excel-файла нормативов остаются внешними источниками Power BI без изменений. `normative_seconds` не включается в PostgreSQL mapping. В Power BI сохраняются текущие правила:

- связь норматива по сети и виду события;
- 5 минут для встречи в сервисной воронке;
- fallback 1,5 минуты без ответа и 3 минуты при ответе;
- рабочий менеджер-день — distinct пара `manager_id × interaction_date` с хотя бы одной задачей;
- `% загрузки = нормативное время / (активные менеджер-дни × 465 минут)`.

## Не переносить

- `InfoRg6003` (`Треды Edna`);
- вычисления предыдущего входящего/исходящего контакта;
- признак `Первое исходящее`;
- технические GUID в пользовательскую модель;
- полные копии справочников CRM и сотрудников.

Пользователь подтвердил отсутствие потребителя у первых трёх пунктов.

## Refresh

- каждые два часа с 08:00 до 22:00 включительно;
- восемь запусков: `08, 10, 12, 14, 16, 18, 20, 22`;
- механизм изменяемого окна и защита от параллельного запуска определяются позднее.

## Блокеры

1. `CONFIRMED business rule`: SV-026 подтверждает 3 103 CRM-взаимодействия 2026 года с 2–3 строками `InfoRg7146`. Каждая строка регистра — отдельный звонок менеджера в рамках одного взаимодействия; report-view сохраняет прямой join и одну строку на звонок. Нормализация запрещена.
2. Технические правила `Marked` и архивных признаков.
3. Контрольные значения.

## Именование Power BI

Предварительное имя факта: `Взаимодействия с клиентами`.

Все пользовательские поля, меры и справочники модели должны называться по-русски. Технические ID скрываются, но используются для связей и distinct.
