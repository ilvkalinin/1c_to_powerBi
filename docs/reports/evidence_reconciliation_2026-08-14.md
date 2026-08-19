# Сверка существующих доказательств — 2026-08-14

Статус: `DOCUMENTARY_AUDIT_COMPLETE / NO_SOURCE_QUERIES_RUN`.

## Уточнение 2026-08-18

После этой сверки появились результаты `SV-093—SV-101`, решения по
рекарринговой единице и 38 строкам детских пакетов, а также три утверждённых
PBIT. Их точное влияние и оставшийся перечень контролей зафиксированы в
[документарной сверке 2026-08-18](documentary_evidence_delta_2026-08-18.md).
Этот документ сохраняет исходный срез 2026-08-14 и не должен читаться как
актуальный список десяти gaps.

## Исправление предыдущего вывода

По всем 31 договорным отчётам уже существуют Stage-2 SQL и server evidence
`SV-054—SV-092` (а также общие `SV-001—SV-053`). Поэтому нельзя назначать
повторную проверку только потому, что в старой матрице стоит
`PARTIALLY VALIDATED` или class C.

BR-018 уточнён: физическая витрина следует согласованному правилу, а не
случайной формулировке старого запроса. Обнаруженные multiplicity, orphan,
state и interval anomalies сохраняются как артефакты потенциальной доработки;
они не являются автоматически ни новой методикой, ни новым вопросом к
пользователю.

## Обозначения

| Статус | Смысл |
|---|---|
| `EVIDENCE_REUSED` | Доказательство уже есть; повторять source control не нужно. |
| `RULE_PRESERVED` | Обнаружено отклонение от идеальной модели, но согласованное правило предписывает воспроизводить текущий результат и сохранить артефакт. |
| `TECHNICAL_GAP` | В документации есть конкретный неисполненный или pending control. Это будущая техническая работа, а не вопрос пользователя и не разрешение изменить правило. |
| `OUT_OF_SCOPE` | Для шести недоговорных отчётов требуется только решение о включении в scope. |

## Договорные отчёты

| № | Отчёт | Сверенный статус | Доказательство / точный остаток |
|---:|---|---|---|
| 1 | KPI Фитнеса | `EVIDENCE_REUSED` | SV-054—061; shared facts уже загружены. |
| 2 | Вовлечение новичков | `EVIDENCE_REUSED` | SV-075/092; class-B conditions уже учтены. |
| 3 | Вовлечение новичков, второй месяц | `RULE_PRESERVED` | SV-076: child/СПТ multiplicity и `RANK()` ties сохраняются. |
| 4 | Подготовка к продлению | `EVIDENCE_REUSED` | SV-077: текущие pairs/границы сохраняются. |
| 5 | Воронка лиды фитнес | `EVIDENCE_REUSED` | SV-078: task→service cardinality зафиксирована. |
| 6 | Загрузка сотрудников | `RULE_PRESERVED` | SV-074: интервалы, СКУД links и кадровые overlaps — артефакты; без нового правила не нормализуются. |
| 7 | Контроль предварительной записи | `RULE_PRESERVED` | SV-072: `VT4352`, orphan enum и document/registry расхождения сохраняются. |
| 8 | Отчёт по ИП | `EVIDENCE_REUSED` | SV-058/068; branch multiplicity уже включена в shared fact. |
| 9 | Посещения Физкульт | `RULE_PRESERVED` | SV-070: 5 избыточных coupon join rows сохраняются. |
| 10 | Уроки и расписание | `RULE_PRESERVED` | SV-073 и SV-LS-001; BR-021 закрывает room-slot edge. |
| 11 | Фитнес воронка | `EVIDENCE_REUSED` | SV-079; cohort/outcome boundary зафиксированы. |
| 12 | Загрузка ОП | `TECHNICAL_GAP` | SV-084: SA-V02—V04 не выполнены из-за timeout/ETIMEDOUT. |
| 13 | Отчёт по поступлениям | `TECHNICAL_GAP` | SV-083: полный movement key, states/sign и recurring-payment key не доказаны. |
| 14 | Отчёт по промокодам | `RULE_PRESERVED` | SV-091: join excess и DAX fallback сохранены по BR-018. |
| 15 | Продажа детских пакетов | `TECHNICAL_GAP` | SV-085: CP-V03—V06 pending для amount/product, returns, states и sentinel dates. |
| 16 | Управление продлением | `RULE_PRESERVED` | SV-081: current same-client/first-start и source cases сохраняются. |
| 17 | Отчёт по %Renew | `EVIDENCE_REUSED` | SV-082: legacy year window и `COUNT(*)` зафиксированы. |
| 18 | Выручка рецепции | `EVIDENCE_REUSED` | SV-050—053; кассир из `_document294` не добавляется. |
| 19 | Записи администраторов | `RULE_PRESERVED` | SV-086: document grain и observed movement/position multiplicity сохраняются. |
| 20 | Новички и гостевые визиты | `TECHNICAL_GAP` | SV-087: first-visit, ACCUNIQ states, outcome и booking attribution pending. |
| 21 | Отчёт по обращениям | `TECHNICAL_GAP` | SV-088: HTML/follow-up, topic/filter, denominator, SLA controls not executed/pending. |
| 22 | Посещаемость клиентов с долгами | `TECHNICAL_GAP` | SV-089: document/prebooking/text/as-of controls not executed; SLA pending. |
| 23 | Посещения Пушкинский | `RULE_PRESERVED` | SV-071: categories and observed coupon multiplicity preserved. |
| 24 | Работа с посещаемостью | `SOURCE_CONTROL_CLOSED` | WA-V06C: полный двухлетний source-side расчёт дневной КБ эквивалентен current-M на четырёх direct anchors; SLA остаётся приёмкой после создания витрины. |
| 25 | Карта администратора | `TECHNICAL_GAP` | SV-002 только подтверждает source availability; Gymmy key/success/card→club не доказаны. |
| 26 | Титульный лист | `EVIDENCE_REUSED` | SV-062—064; Excel branches remain external. |
| 27 | Маркетинговая воронка | `TECHNICAL_GAP` | SV-080/BR-020 фиксируют правило, но physical task-code/join/state controls остаются. |
| 28 | Клиентская база | `RULE_PRESERVED` | SV-069: 00:00 boundary и раздельный club/network dedupe подтверждены. |
| 29 | Выручка ДПФУ | `EVIDENCE_REUSED` | SV-054—057 и four shared facts validated. |
| 30 | Членство для правления | `SOURCE_CONTROL_CLOSED` | Эталонный домен поступлений подтверждён SV-096 и SV-112—SV-130; ненаблюдаемое ПКО `RecordKind=1` сохранено по BR-018, а board/non-additive reconciliation выполняется после создания модели. |
| 31 | Свод выручка ГК | `EVIDENCE_REUSED` | SV-035—050/066; external Excel remains outside PostgreSQL. |

Итог: 21 отчёт не требует нового source control (`EVIDENCE_REUSED` или
`RULE_PRESERVED`); 10 имеют конкретные технические gaps; 6 не входят в
договорный scope. Ни один из десяти gaps не требует от пользователя повторно
утверждать бизнес-правило.

## Вне договорного scope

Карты будущего периода, Edna, Несчастные случаи, Пульс клуба 2026, Группа VK
Физкульт (Анализ постов) и Директ имеют статус `OUT_OF_SCOPE`. Они не являются
техническими blockers договорных 31 отчётов и не требуют анализа, пока
пользователь не включит их в scope.

## Следствие для global gate

Реестр вопросов и план закрытия следует читать с этой сверкой: не нужно
повторять уже выполненные controls и нельзя выдавать `RULE_PRESERVED` за
`DECISION_REQUIRED`. Для полной готовности к созданию всех витрин остаются
только десять перечисленных `TECHNICAL_GAP`; их будущая проверка должна быть
одним явно разрешённым read-only пакетом без DDL/DML и без изменения
согласованных правил.
