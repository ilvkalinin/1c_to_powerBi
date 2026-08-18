# Точный checklist до полного review global gate — 2026-08-18

Статус: `DOCUMENTARY_CHECKLIST / NO_SOURCE_QUERIES_RUN`.

## Назначение и граница

Это сводка только уже названных controls для девяти отчётов из
[документарной сверки](documentary_evidence_delta_2026-08-18.md). Она не
открывает пакет, не разрешает Stage 2/Stage 3, DDL/DML или изменение текущих
SQL/M/DAX. Контроль считается закрытым только при сохранённом read-only
результате либо при уже принятом пользовательском правиле; шаблон SQL или
старая отметка `NOT_EXECUTED` доказательством не являются.

## Предварительные source controls

| Отчёт | Оставшиеся control IDs | Что именно должно быть доказано без изменения правила |
|---|---|---|
| Отчёт по поступлениям | MR-V03, MR-V04—V10, MR-V11, MR-V12, MR-V14—V15 | states/sign, взаимное исключение 14 recorder-веток, сохранение count/sum после join, predecessor ties, freeze/classification, пять KPI с уже подтверждённой единицей `contract × payment_period`, роли дат, воспроизводимый rerun и SLA. `SV-096` уже закрыл только спор о «дубликатах ежемесячного платежа». |
| Продажа детских пакетов | CP-V03—V06 из SV-085/095 | technical признак и знак возврата, states чека и регистра, допустимость current receipt filter и контрольные значения. Правило для 38 строк (`'0'`, `'0'`, `0`) повторно не проверяется как выбор метода. |
| Новички и гостевые визиты | NV-V02, NV-V05, NV-V06, NV-V09 | отсутствие размножения `AccumRg7575 → Document325/Reference59`; 12 утверждённых ACCUNIQ-кодов в `Reference163`, states и `Fld7585`; границы outcome 0/44/45; latest state `InfoRg7006` для booking attribution. |
| Отчёт по обращениям | CR-V08, CR-V10—V11 | business visit grain без размножения contract join; равенство текущему Power BI на зафиксированном периоде; changes/deletions, rerun и SLA. `SV-098` и CR-V05D—G уже закрыли feedback core, Jivo, статусы и funnel ID. |
| Посещаемость клиентов с долгами | DV-V05, DV-V06, DV-V07 | as-of сверка минимум на двух датах/клубах, физически подтверждённая классификация current visit/service scope без подстановки нового фильтра, end-to-end refresh SLA. `SV-099` уже закрыл physical movement key и document branches. |
| Работа с посещаемостью | WA-V06, historical часть WA-V08 | дневное покрытие/численность `client_base_daily` и измеренный годовой refresh SLA. Внешние Excel-наборы шкафчиков и мощности в этот checklist не входят. |
| Карта администратора | независимая дневная сверка (ID не присвоен) | для одного зафиксированного периода равенство дневных counts по дате × клубу × направлению с текущим Power BI. `SV-100`/AC-V05 уже закрыли event key, success и card→club. |
| Маркетинговая воронка | MF-V08, MF-V09—V10 | exact DAX накопленного трафика на согласованном месяце; equality Power BI по task/contract/conversion/plan-fact; rerun, changes и SLA. `SV-101` и MF-V04/V06/V07/V07C не повторяются. |
| Членство для правления | наследуемые MR controls; MB-V01—V08 | source states/keys из общего домена поступлений, равенство пяти KPI, сохранение non-additive расчётов, роли дат, filter propagation и SLA. Внешние Excel-планы остаются в Power BI и не загружаются в PostgreSQL. |

## Что уже закрыто и не включается повторно

- «Загрузка ОП»: `SV-093` завершил исходный technical gap.
- Для рекарринга: `SV-096` подтвердил группу `contract × payment_period` и
  сумму всех её движений; нельзя снова искать «один physical monthly key».
- Для 38 строк детских пакетов: fallback `product_id = '0'`,
  `product_name = '0'`, `package_amount = 0` уже принято пользователем.
- Новички/гости: PBIT уже зафиксировал 12 ACCUNIQ-кодов, знаковое правило и
  итог 1/2; точный набор услуг не подбирается по названию.
- Обращения: полный feedback-source для speed/quality, Jivo, три статуса и
  funnel `Продажа клип карты Рецепция` уже определены текущими материалами.
- Маркетинговая воронка: PBIT-алгоритм, task-code scope, bridge cardinality,
  payment type и наблюдаемые source states уже доказаны/сохранены.

## Неразрешимое без процессного выбора место

`CR-V10`, независимая дневная сверка «Карты администратора», `MF-V09`, значительная часть `MB-V01—V08` и часть
MR-V11 требуют сравнить **созданный** PostgreSQL-объект с текущим Power BI.
Их нельзя буквально выполнить до создания этого объекта. Одновременно
текущая формулировка global gate запрещает создание, пока не закрыты все
вопросы.

Поэтому для полного снятия gate нужен один процессный выбор:

1. считать эти output-reconciliation и SLA checks условиями product admission
   после создания объекта, но до его подключения к Power BI; либо
2. разрешить отдельный read-only пакет, который строит эквивалентные временные
   source projections без создания `mart`-объектов и сверяет их с Power BI.

Без одного из этих вариантов проект оказывается в цикле: проверка требует
объекта, а объект запрещён до проверки. Этот checklist не выбирает вариант
самостоятельно.

## Основания

- [документарная сверка 2026-08-18](documentary_evidence_delta_2026-08-18.md);
- [реестр нерешённых вопросов](global_unresolved_questions_register_2026-08-14.md);
- `docs/reports/*_query_review.md`, `docs/mappings/*.md` и
  `docs/source_metadata/server_validation_2026-08-14.md` по указанным ID.
