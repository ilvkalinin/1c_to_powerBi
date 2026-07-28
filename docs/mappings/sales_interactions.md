# Source-to-target mapping: взаимодействия отдела продаж

Статус: `BUSINESS MAPPING COMPLETE / TECHNICAL VALIDATION DEFERRED`.

Mapping основан на текущих SQL/M/DAX, metadata и решениях пользователя 2026-07-24. Бизнес-гранулярность и правила подтверждены. Кардинальность телефонии и технические joins требуют проверки, поэтому физический объект и DDL пока не выбираются.

## Предварительная гранулярность

Кандидат:

> одна строка на взаимодействие `Reference67.ID`.

Логический ключ:

> `interaction_id`.

Эта гранулярность нужна для медианы длительности и детальной таблицы запланированных взаимодействий. Если одно взаимодействие содержит несколько самостоятельных звонков, потребуется отдельное решение после проверки `InfoRg7146`; смешивать их в одной строке без правила нельзя.

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
| `event_type_name` | русская категория события | mapping текущих GUID | `text`/малый код | да | current mapping | неизвестные типы |
| `interaction_state_id` | состояние | `Reference67.Fld829` | UNKNOWN | да | CONFIRMED source | удалённые справочники |
| `interaction_state_name` | состояние для визуала | `Reference224.Description`; звонки `В процессе → Закрыто` по текущему DAX | `text`/малый код | да | current rule | подтвердить переклассификацию |
| `interaction_status_id` | статус | `Reference67.Fld830` | UNKNOWN | да | CONFIRMED source | перечень значений |
| `interaction_status_name` | выполнено / не выполнено / отменено | mapping текущих GUID | `text`/малый код | да | current mapping | неизвестные статусы |
| `manager_id` | стабильный оператор | `Reference67.Fld824` | UNKNOWN | нет | CONFIRMED source | пустые исполнители |
| `manager_name` | имя оператора | `Reference225.Description` | `text` | нет | CONFIRMED need | не использовать как ключ |
| `operator_club_id` | клуб задания, в котором трудоустроен менеджер | `Reference106.Fld1195`; требуется совпадение с `InfoRg6291.Fld6293` на дату создания | UNKNOWN | нет | CONFIRMED — user decision | employee-club interval cardinality |
| `network_name` | Физкульт / Пушкинский | по подтверждённому клубу | `text`/малый код | нет | current rule | справочник клубов |
| `client_key` | стабильный клиент | `Reference106.Fld1196` | UNKNOWN | да | CONFIRMED source | считать ли строки без клиента |
| `client_code` | код клиента | `Reference141X1.Code` | `text` | да | CONFIRMED need | доступ |
| `client_name` | ФИО в детальной таблице | `Reference141X1.Description` | `text` | да | CONFIRMED need | PII access |
| `client_phone` | телефон в детальной таблице | `Reference141X1.Fld1531` | `text` | да | CONFIRMED need | PII access |
| `tenure_type` | New / Ex / Renew | `Reference106.Fld1190` + текущий GUID mapping | `text`/малый код | да | CONFIRMED current | неизвестные значения |
| `client_status` | действительный / бывший / потенциальный | `Reference106.Fld1204` + текущий GUID mapping | `text`/малый код | да | CONFIRMED current | неизвестные значения |
| `funnel_id` | стабильная воронка | `Reference106.Fld1191` | UNKNOWN | нет | CONFIRMED source | фильтр по ID |
| `funnel_name` | вид воронки | `Reference89.Description` | `text` | нет | CONFIRMED need | текущие три значения |
| `campaign_id` | маркетинговая кампания | `Reference106.Fld1197` | UNKNOWN | да | CONFIRMED source | Jivo exclusion |
| `campaign_name` | название кампании | `Reference145.Description` | `text` | да | current need | не использовать как filter key |
| `channel_id` | канал | `Reference106.Fld1194` | UNKNOWN | да | CONFIRMED source | фактическое использование |
| `cancellation_reason` | причина отмены | `Reference67.Fld828 → Reference202.Description` | `text` | да | current source | используется ли визуалом |
| `interaction_count` | вклад строки в количество задач | `1`, если код/ключ клиента непустой, иначе `0` | `smallint` | нет | CONFIRMED — current measure | null client reconciliation |

## Отбор сотрудников

Текущий M оставляет должности:

- `Менеджер ОП`;
- `Старший менеджер ОП`.

Интервал `InfoRg6291.Fld6298..Fld6299` проверяется на `Reference67.Fld823` (`ДатаСоздания`) — CONFIRMED.

Связывать по `employee_id` и `operator_club_id`, а не по имени. Проверка должна использовать `EXISTS`/эквивалентную семиджойн-логику, чтобы несколько строк настроек сотрудника не размножали взаимодействие.

## Отбор воронок

Текущая реализация оставляет:

- `Продажа клубной карты`;
- `Сервисная воронка ОП`;
- `Корпоративная продажа`.

Из сервисной воронки исключаются кампании:

- `Заявка c Jivo-site Физкульт`;
- `Заявка с Jivo-site (Пушкинский)`.

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

1. Кардинальность `Reference67 → InfoRg7146` и правило нескольких звонков.
2. Кардинальность настроек сотрудника после совпадения manager + club + position + interval.
3. Технические правила `Marked` и архивных признаков.
4. Фактические типы и объёмы.
5. Контрольные значения.

## Именование Power BI

Предварительное имя факта: `Взаимодействия с клиентами`.

Все пользовательские поля, меры и справочники модели должны называться по-русски. Технические ID скрываются, но используются для связей и distinct.
