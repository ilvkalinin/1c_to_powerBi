# Data contract: «Свод выручка ГК»

Статус: `DESIGNED / IMPLEMENTATION DEFERRED / TECHNICAL VALIDATION REQUIRED`.
Контракт покрывает только PostgreSQL-факт фактической выручки. Планы и бюджеты
по подтверждённому решению остаются отдельными Excel-фактами Power BI.

## Общие параметры

| Параметр | Значение | Статус / доказательство |
|---|---|---|
| Объект PostgreSQL | `mart.revenue_group_summary_daily` | ACCEPTED — ADR-0010 |
| Таблица Power BI | `Свод выручка ГК` | CONFIRMED naming rule |
| Назначение | факт статей выручки `02`–`13` по дню и клубу | CONFIRMED |
| Гранулярность | дата факта × клуб × статья | CONFIRMED — ADR-0010/mapping |
| Логический ключ | `(revenue_date, club_id, revenue_article_code)` | ASSUMPTION pending uniqueness tests |
| Хранение | BR-003 | CONFIRMED user decision |
| Режим Power BI | `Import`, ежедневно | CONFIRMED current report; SLA UNKNOWN |
| Исправления/удаления | атомарный полный пересчёт горизонта | CONFIRMED design; states pending |
| Таблица дат / поле | `Календарь` / `Дата` | CONFIRMED current DAX |
| Инкрементальное поле | отсутствует | UNKNOWN — event date не watermark |

## Колонки

| PostgreSQL | Power BI | PostgreSQL тип | Power BI тип | NULL | Роль | Аддитивность | Скрыть | Mapping |
|---|---|---|---|---|---|---|---|---|
| `revenue_date` | `Дата` | `date` | Date | нет | FK календаря | не мера | нет | `revenue_date` |
| `club_id` | `Код клуба` | `text` | Text | нет | FK клуба | не мера | да | `club_id` |
| `revenue_article_code` | `Код статьи` | `text` | Text | нет | FK статьи | не мера | да | `revenue_article_code` |
| `revenue_amount` | `Выручка` | `numeric` | Fixed decimal number | нет | показатель | аддитивна | нет | `revenue_amount` |
Если несколько ветвей законно составляют одну статью/день/клуб, PostgreSQL
сначала сверяет их во временном source-side наборе, затем агрегирует до
логического ключа. Технический `source_branch` не входит в контракт.

## Связи

| От | К | Кардинальность | Фильтрация | Статус |
|---|---|---|---|---|
| `Календарь[Дата]` | факт `[Дата]` | `1:*` | однонаправленная | CONFIRMED BY DESIGN; unique date pending |
| `Клубы[Код клуба]` | факт `[Код клуба]` | `1:*` | однонаправленная | technical FK pending |
| `Статьи выручки[Код статьи]` | факт `[Код статьи]` | `1:*` | однонаправленная | article coverage pending |

Excel-таблицы планов и бюджетов не соединяются с фактом. Они получают тот же
контекст только через `Календарь`, `Клубы` и `Статьи выручки`; отсутствующие
в Excel разрезы не получают искусственной связи. `01.ВЫРУЧКА ВСЕГО` —
отключённая/логическая статья только для DAX, не строка факта.

## Граница вычислений

PostgreSQL: source-state filters, знаки, ID-классификация, anti-overlap,
дневная агрегация. Power Query: готовый факт, типизация, сохранённые Excel
планы/бюджеты. DAX: текущий факт, статья 01, плановые меры, линейный и
коэффициентный план, LY/YTD, отношения и цвет.

## Условия принятия

1. Уникальность логического ключа и отсутствие orphan club/article.
2. Сверка сумм/строк каждой source branch с зафиксированным Power BI snapshot.
3. Состояния, знаки, документы членства и пересечение 7575/7646 подтверждены.
4. Excel 07–13 имеет однозначные mapping клуб/статья и уникальный дневной
   результат.
5. Модель Power BI подтверждает три связи `1:*`, без M2M/fact-to-fact.
6. Проверены границы BR-003, rerun, изменения/удаления и performance/SLA.
