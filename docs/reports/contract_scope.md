# Договорной перечень отчётов

Источник: изображение перечня из договора, предоставленное пользователем 2026-07-24.

Статус перечня: `CONFIRMED`. В договор входит 31 отчёт. Более широкий рабочий
Excel-перечень не меняет договорный scope без отдельного решения.

Обозначения этапов:

- `COMPLETE` — соответствующий артефакт существует;
- `PROPOSED` / `DESIGNED` — артефакт существует, но техническая валидация или реализация отложены;
- `NOT STARTED` — артефакта нет;
- `DEFERRED` — работа сознательно не запускалась; это не завершение этапа.

На 2026-07-28 бизнес-анализ завершён по 15 из 31 отчёта. Реализованных
витрин и завершённой технической валидации нет.

| № | Блок | Наименование отчёта | Business analysis | Source mapping | Architecture | Data contract | Implementation | Validation |
|---:|---|---|---|---|---|---|---|---|
| 1 | Фитнес | KPI Фитнеса | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED |
| 2 | Фитнес | Вовлечение новичков | COMPLETE | COMPLETE | DESIGNED — ADR-0008 | COMPLETE — `newcomer_engagement` | DEFERRED | DEFERRED — technical validation |
| 3 | Фитнес | Вовлечение новичков Второй месяц | COMPLETE | COMPLETE — `newcomer_engagement_second_month` | DESIGNED — ADR-0009 | COMPLETE — `newcomer_engagement_second_month` | DEFERRED | DEFERRED — technical validation |
| 4 | Фитнес | Подготовка к продлению | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED |
| 5 | Фитнес | Воронка лиды фитнес | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED |
| 6 | Фитнес | Загрузка сотрудников | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED |
| 7 | Фитнес | Контроль предварительной записи | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED |
| 8 | Фитнес | Отчет по ИП | COMPLETE | COMPLETE — `ip_training` | NOT STARTED | NOT STARTED | DEFERRED | DEFERRED — technical validation |
| 9 | Фитнес | Посещения Физкульт | COMPLETE | COMPLETE — `visits_fizkult` | PROPOSED / REVISION REQUIRED — ADR-0003 | NOT STARTED | DEFERRED | DEFERRED — technical validation |
| 10 | Фитнес | Уроки и расписание | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED |
| 11 | Фитнес | Фитнес воронка | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED |
| 12 | Продажи | Загрузка ОП | COMPLETE | COMPLETE — `sales_interactions` | NOT STARTED | NOT STARTED | DEFERRED | DEFERRED — technical validation |
| 13 | Продажи | Отчет по поступлениям | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED |
| 14 | Продажи | Отчет по промокодам | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED |
| 15 | Продажи | Продажа детских пакетов | COMPLETE | COMPLETE — `children_package_sales` | NOT STARTED | NOT STARTED | DEFERRED | DEFERRED — technical validation |
| 16 | Продажи | Управление продлением | COMPLETE | COMPLETE | PROPOSED — ADR-0007 | COMPLETE — `renewal_management` | DEFERRED | DEFERRED — technical validation |
| 17 | Продажи | Отчет по %Renew | COMPLETE | COMPLETE | PROPOSED — ADR-0006 | COMPLETE — `renew_contract_usage` | DEFERRED | DEFERRED — technical validation |
| 18 | Гостеприимство | Выручка рецепции | COMPLETE | COMPLETE | PROPOSED — ADR-0005 | COMPLETE — `reception_revenue` | DEFERRED | DEFERRED — technical validation |
| 19 | Гостеприимство | Записи администраторов | COMPLETE | COMPLETE | PROPOSED — ADR-0004 | COMPLETE — `administrator_bookings` | DEFERRED | DEFERRED — technical validation |
| 20 | Гостеприимство | Новички и гостевые визиты | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED |
| 21 | Гостеприимство | Отчет по обращениям | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED |
| 22 | Гостеприимство | Отчет по посещаемости клиентов с долгами | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED |
| 23 | Гостеприимство | Посещения Пушкинский | COMPLETE | COMPLETE — `visits_pushkinsky` | PROPOSED / REVISION REQUIRED — ADR-0003 | NOT STARTED | DEFERRED | DEFERRED — technical validation |
| 24 | Гостеприимство | Работа с посещаемостью | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED |
| 25 | Гостеприимство | Карта администратора | COMPLETE | COMPLETE — `administrator_card` | NOT STARTED | NOT STARTED | DEFERRED | DEFERRED — technical verification |
| 26 | Гостеприимство | Титульный лист | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED |
| 27 | Маркетинг | Воронка | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED |
| 28 | Маркетинг | Клиентская база | COMPLETE | COMPLETE — `client_base`, `client_base_retention` | COMPLETE — ADR-0002 | COMPLETE — `client_base` | DEFERRED | DEFERRED — DB tests |
| 29 | Для правления | Выручка ДПФУ | COMPLETE | COMPLETE — `dpfu_revenue` | PROPOSED — shared direction ADR-0005; product identity unresolved | NOT STARTED | DEFERRED | DEFERRED — technical validation |
| 30 | Для правления | Отчет членство для правления | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED | NOT STARTED |
| 31 | Для правления | Свод выручка ГК | COMPLETE — `revenue_group_summary` | COMPLETE — `revenue_group_summary` | DESIGNED — ADR-0010 | COMPLETE — `revenue_group_summary` | DEFERRED | DEFERRED — technical validation |

Осталось начать бизнес-анализ 16 отчётов. После завершения каждого отчёта
обновляются все шесть статусов его строки; `COMPLETE` нельзя ставить без
соответствующего файла.

## Расхождение с рабочим Excel

В рабочем Excel было 37 строк. Следующие шесть отчётов отсутствуют в
договорном перечне и имеют статус `ВНЕ ДОГОВОРНОГО SCOPE`:

- Карты будущего периода;
- Edna;
- Несчастные случаи;
- Пульс клуба 2026;
- Группа VK Физкульт (Анализ постов);
- Директ.
