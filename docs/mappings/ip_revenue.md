# Source-to-target mapping: выручка ИП

Статус: `STAGE_3 DML APPROVAL PENDING / current club rule CONFIRMED`.

## Гранулярность и граница

Кандидат целевой строки:

> дата оплаты × клуб движения (может отсутствовать) × услуга договора ИП.

Источник — `AccumRg7370`; факт не объединяется с `mart.ip_training_daily`:
у тренировок дата оказания и клиент/сотрудник, у выручки ИП дата оплаты и
денежная сумма. Это отдельный компактный shared fact для KPI Фитнеса и ДПФУ.

## Целевые поля

| Колонка | Источник / преобразование | Тип | NULL | Статус / evidence |
|---|---|---|---|---|
| `revenue_date` | `AccumRg7370._Period::date` | `date` | нет | CONFIRMED — current M; S3-IP-REVENUE-001 physical type `timestamp` |
| `club_id` | `encode(AccumRg7370._Fld7372RRef, 'hex')` | `text` | да | CONFIRMED — current M делает `LEFT JOIN` и сохраняет пустой клуб; BR-018 запрещает подстановку клуба договора без отдельного решения |
| `service_id` | `AccumRg7370._Fld7371RRef → Reference59._Fld685RRef → Reference163._IDRRef`, encoded | `text` | нет | CONFIRMED — SV-019—SV-022, S3-IP-REVENUE-001; прямой `_Fld7378RRef` не является fallback |
| `service_name` | `Reference163._Description::text` через тот же путь договора | `text` | нет | CONFIRMED — current M uses the same field in its qualification; `ILIKE '%ИП%'` ensures it is not blank |
| `revenue_amount` | `SUM(AccumRg7370._Fld7377)` | `numeric(18,2)` | нет | CONFIRMED — source `numeric`; знак сохраняется |

## Current-rule qualification

- дата — dynamic bounded BR-003, а не static legacy start date;
- `RecordKind = 0` — CONFIRMED current M;
- услуга отбирается по `Reference163.Description ILIKE '%ИП%'` через договор —
  CONFIRMED current M / BR-018. Стабильный классификатор услуги пока не
  подтверждён и не подменяется предположением;
- `_Active` не становится новым фильтром: в qualified scope найдены 3
  неактивные строки, и current M их сохраняет.

## S3-IP-REVENUE-001 — source snapshot 2026-08-14

BR-003 horizon `2025-01-01`—`2027-01-01`, one `REPEATABLE READ READ ONLY`
source snapshot:

| Контроль | Результат |
|---|---:|
| qualified payments | 178 022 |
| candidate date × movement-club × service rows | 47 151 |
| source / grouped revenue | 268 944 858,22 / 268 944 858,22 |
| duplicate technical keys | 0 |
| inactive / negative / zero movements | 3 / 82 738 / 4 |
| payment with matched movement club | 85 973 |
| payment with missing movement club and present contract club | 92 049; сумма 1 973 090,65 |
| both clubs present but different | 19; сумма 44 990,00 |

`Reference59._Fld687RRef` покрывает все 178 022 qualified payments, но это
клуб договора. Current M использует `LEFT JOIN` от `AccumRg7370._Fld7372RRef`
к `Reference132` и сохраняет `NULL` клуба; подстановка клуба договора изменит
атрибуцию 92 049 строк. BR-018 требует сохранить пустой `club_id` в первом
релизе; физический ключ должен технически различать такую строку без подмены
значения для Power BI.

## Пул возможных методических доработок

| Идея | Наблюдаемый эффект | Статус |
|---|---|---|
| Заполнять пустой movement-club клубом договора `Reference59._Fld687RRef` | изменит клубную атрибуцию 92 049 current qualified оплат на 1 973 090,65; 19 строк с обоими клубами уже различаются | NOT FIRST RELEASE — отдельное явное бизнес-решение |
