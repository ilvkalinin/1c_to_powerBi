# Договорной перечень отчётов

Источник: изображение перечня из договора, предоставленное пользователем 2026-07-24.

Статус перечня: `CONFIRMED`. В договор входит 31 отчёт. Более широкий рабочий
Excel-перечень не меняет договорный scope без отдельного решения.

Обозначения этапов:

- `COMPLETE` — соответствующий артефакт существует;
- `PROPOSED` / `DESIGNED` — артефакт существует, но техническая валидация или реализация отложены;
- `NOT STARTED` — артефакта нет;
- `DEFERRED` — работа сознательно не запускалась; это не завершение этапа.

На 2026-08-03 бизнес-анализ, source mapping, проектная архитектура и Power BI
data contract оформлены по 31 из 31 отчёта. Реализованных витрин и завершённой
технической валидации нет.

| № | Блок | Наименование отчёта | Business analysis | Source mapping | Architecture | Data contract | Implementation | Validation |
|---:|---|---|---|---|---|---|---|---|
| 1 | Фитнес | KPI Фитнеса | COMPLETE — `kpi_fitness` | COMPLETE — `kpi_fitness` | DESIGNED — ADR-0012 | COMPLETE — `kpi_fitness` | DEFERRED | COMPLETE — SV-054—SV-061 |
| 2 | Фитнес | Вовлечение новичков | COMPLETE | COMPLETE | DESIGNED — ADR-0008 | COMPLETE — `newcomer_engagement` | DEFERRED | PARTIALLY VALIDATED — SV-075; Stage 3 deferred |
| 3 | Фитнес | Вовлечение новичков Второй месяц | COMPLETE | COMPLETE — `newcomer_engagement_second_month` | DESIGNED — ADR-0009 | COMPLETE — `newcomer_engagement_second_month` | DEFERRED | PARTIALLY VALIDATED — SV-076; Stage 3 deferred |
| 4 | Фитнес | Подготовка к продлению | COMPLETE — `preparation_renewal` | COMPLETE — `preparation_renewal` | DESIGNED — ADR-0013 | COMPLETE — `preparation_renewal` | DEFERRED | PARTIALLY VALIDATED — SV-077; Stage 3 deferred |
| 5 | Фитнес | Воронка лиды фитнес | COMPLETE — `fitness_leads_funnel` | COMPLETE — `fitness_leads_funnel` | DESIGNED — ADR-0011 | COMPLETE — `fitness_leads_funnel` | DEFERRED | PARTIALLY VALIDATED — SV-078; Stage 3 deferred |
| 6 | Фитнес | Загрузка сотрудников | COMPLETE — `employee_workload` | COMPLETE — `employee_workload` | DESIGNED — ADR-0014 | COMPLETE — `employee_workload` | DEFERRED | PARTIALLY VALIDATED — SV-074; Stage 3 deferred |
| 7 | Фитнес | Контроль предварительной записи | COMPLETE — `prebooking_control` | COMPLETE — `prebooking_control` | DESIGNED — ADR-0015 | COMPLETE — `prebooking_control` | DEFERRED | PARTIALLY VALIDATED — SV-072; Stage 3 deferred |
| 8 | Фитнес | Отчет по ИП | COMPLETE | COMPLETE — `ip_training` | DESIGNED — ADR-0025 | COMPLETE — `ip_training` | DEFERRED | DEFERRED — technical validation |
| 9 | Фитнес | Посещения Физкульт | COMPLETE | COMPLETE — `visits_fizkult` | DESIGNED — ADR-0003 | COMPLETE — `visits_fizkult` | DEFERRED | PARTIALLY VALIDATED — SV-070; Stage 3 deferred |
| 10 | Фитнес | Уроки и расписание | COMPLETE — `lessons_schedule` | COMPLETE — `lessons_schedule` | DESIGNED — ADR-0015 | COMPLETE — `lessons_schedule` | DEFERRED | PARTIALLY VALIDATED — SV-073; Stage 3 deferred |
| 11 | Фитнес | Фитнес воронка | COMPLETE — `fitness_funnel` | COMPLETE — `fitness_funnel` | DESIGNED — ADR-0026 | COMPLETE — `fitness_funnel` | DEFERRED | DEFERRED — technical validation |
| 12 | Продажи | Загрузка ОП | COMPLETE | COMPLETE — `sales_interactions` | DESIGNED — ADR-0016 | COMPLETE — `sales_interactions` | DEFERRED | DEFERRED — technical validation |
| 13 | Продажи | Отчет по поступлениям | COMPLETE — `membership_receipts` | COMPLETE — `membership_receipts` | DESIGNED — ADR-0017 | COMPLETE — `membership_receipts` | DEFERRED | DEFERRED — technical validation |
| 14 | Продажи | Отчет по промокодам | COMPLETE — `promo_codes` | COMPLETE — `promo_codes` | DESIGNED — ADR-0018 | COMPLETE — `promo_codes` | DEFERRED | DEFERRED — technical validation |
| 15 | Продажи | Продажа детских пакетов | COMPLETE | COMPLETE — `children_package_sales` | DESIGNED — ADR-0019 | COMPLETE — `children_package_sales` | DEFERRED | DEFERRED — technical validation |
| 16 | Продажи | Управление продлением | COMPLETE | COMPLETE | PROPOSED — ADR-0007 | COMPLETE — `renewal_management` | DEFERRED | DEFERRED — technical validation |
| 17 | Продажи | Отчет по %Renew | COMPLETE | COMPLETE | PROPOSED — ADR-0006 | COMPLETE — `renew_contract_usage` | DEFERRED | DEFERRED — technical validation |
| 18 | Гостеприимство | Выручка рецепции | COMPLETE | COMPLETE | PROPOSED — ADR-0005 | COMPLETE — `reception_revenue` | DEFERRED | DEFERRED — technical validation |
| 19 | Гостеприимство | Записи администраторов | COMPLETE | COMPLETE | PROPOSED — ADR-0004 | COMPLETE — `administrator_bookings` | DEFERRED | DEFERRED — technical validation |
| 20 | Гостеприимство | Новички и гостевые визиты | COMPLETE — `newcomer_guest_visits` | COMPLETE — `newcomer_guest_visits` | DESIGNED — ADR-0020 | COMPLETE — `newcomer_guest_visits` | DEFERRED | DEFERRED — technical validation |
| 21 | Гостеприимство | Отчет по обращениям | COMPLETE — `calls_report` | COMPLETE — `calls_report` | DESIGNED — ADR-0016 | COMPLETE — `calls_report` | DEFERRED | DEFERRED — technical validation |
| 22 | Гостеприимство | Отчет по посещаемости клиентов с долгами | COMPLETE — `visits_debt` | COMPLETE — `visits_debt` | DESIGNED — ADR-0021 | COMPLETE — `visits_debt` | DEFERRED | DEFERRED — technical validation |
| 23 | Гостеприимство | Посещения Пушкинский | COMPLETE | COMPLETE — `visits_pushkinsky` | DESIGNED — ADR-0003 | COMPLETE — `visits_pushkinsky` | DEFERRED | PARTIALLY VALIDATED — SV-071; Stage 3 deferred |
| 24 | Гостеприимство | Работа с посещаемостью | COMPLETE — `work_attendance` | COMPLETE — `work_attendance` | DESIGNED — ADR-0022 | COMPLETE — `work_attendance` | DEFERRED | DEFERRED — technical validation |
| 25 | Гостеприимство | Карта администратора | COMPLETE | COMPLETE — `administrator_card` | DESIGNED — ADR-0023 | COMPLETE — `administrator_card` | DEFERRED | DEFERRED — technical verification |
| 26 | Гостеприимство | Титульный лист | COMPLETE — `title_sheet` | COMPLETE — `title_sheet` | DESIGNED — ADR-0024 | COMPLETE — `title_sheet` | DEFERRED | COMPLETE — SV-062—SV-064 |
| 27 | Маркетинг | Воронка | COMPLETE — `marketing_funnel` | COMPLETE — `marketing_funnel` | DESIGNED — REUSE ADR-0011 | COMPLETE — `marketing_funnel` | DEFERRED | DEFERRED — technical validation |
| 28 | Маркетинг | Клиентская база | COMPLETE | COMPLETE — `client_base`, `client_base_retention` | COMPLETE — ADR-0002 | COMPLETE — `client_base` | DEFERRED | DEFERRED — DB tests |
| 29 | Для правления | Выручка ДПФУ | COMPLETE | COMPLETE — `dpfu_revenue` | DESIGNED — ADR-0005/0012/0025 | COMPLETE — `dpfu_revenue` | DEFERRED | DEFERRED — technical validation |
| 30 | Для правления | Отчет членство для правления | COMPLETE — `membership_board` | COMPLETE — `membership_board` | DESIGNED — REUSE ADR-0017 | COMPLETE — `membership_board` | DEFERRED | DEFERRED — technical validation |
| 31 | Для правления | Свод выручка ГК | COMPLETE — `revenue_group_summary` | COMPLETE — `revenue_group_summary` | DESIGNED — ADR-0010 | COMPLETE — `revenue_group_summary` | DEFERRED | DEFERRED — technical validation |

Локальные бизнес-анализ, mapping, архитектура и Power BI-контракт завершены по
31 из 31 отчёта. После завершения каждого отчёта обновляются все шесть статусов его строки;
`COMPLETE` нельзя ставить без соответствующего файла.

## Расхождение с рабочим Excel

В рабочем Excel было 37 строк. Следующие шесть отчётов отсутствуют в
договорном перечне и имеют статус `ВНЕ ДОГОВОРНОГО SCOPE`:

- Карты будущего периода;
- Edna;
- Несчастные случаи;
- Пульс клуба 2026;
- Группа VK Физкульт (Анализ постов);
- Директ.
