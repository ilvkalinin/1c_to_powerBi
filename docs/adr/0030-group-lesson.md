# ADR-0030: факт группового занятия

- Статус: `IMPLEMENTED / initial BR-003 load VALIDATED — S3-GL-001—003`
- Дата: 2026-08-14
- Потребители: «Контроль предварительной записи», «Уроки и расписание»

## Решение

Создать `mart.group_lesson` с grain одно непомеченное `Document279`.
Витрина хранит документные разрезы занятия, вместимость, тип бесплатной
программы, итог активных записей и итог пришедших.

## Архитектура и refresh

Source read-only extract забирает только base lesson и однострочный
`InfoRg8675` в BR-003 horizon. На VM-2 temporary source stage соединяется с
`mart.prebooking_state_event` по ID занятия и ветви `GZ`; это исключает
дублирование правила квалификации state-event. Затем выполняется atomic full
rebuild одной physical table. Постоянный raw stage, новая реплика 1С и
watermark не создаются.

`mart.prebooking_state_event` обновляется раньше `mart.group_lesson` в том же
цикле. Если shared state fact не подтверждён, group refresh не запускается.

## Последствия

- Меры заполненности остаются в DAX: `SUM(active_booking_count) / SUM(capacity)`
  и `SUM(arrived_count) / SUM(capacity)`;
- текущее правило “платные прибытия, иначе бесплатные” рассчитывается в SQL
  как стабильное свойство одной строки занятия;
- нет fact-to-fact relation: Power BI использует общие calendar и dimensions;
- полный rebuild выбран без непроверенного watermark; индекс помимо unique key
  пока не добавляется — performance evidence отсутствует.

Initial load 2026-08-14 reconciled 301,237 lessons, capacity sum 5,951,952
and free-program arrivals 1,351,360 exactly to the source snapshot.
