# S3-RGS-REUSE-005: убрать временную ветвь рецепции из свода

Дата согласования: 2026-08-20. Статус: `COMPLETED / VALIDATED`.

Пользователь подтвердил перевод статьи `05.РЕЦЕПЦИЯ` на independently
reconciled общий рецепционный scope, чтобы не поддерживать вторую source-side
реализацию тех же правил.

## Scope

1. Изменить existing loader `scripts/load_revenue_group_summary.py`:
   статья `05.РЕЦЕПЦИЯ` агрегируется из
   `mart.ancillary_revenue_movement WHERE revenue_scope = 'reception'` до
   `дата × клуб`; временный direct source extract сохраняет только `02` и `06`.
2. Сохранить без изменений reuse `03`/`04`, правила BR-003, grain и все
   внешние Power BI/Excel границы. New objects и DDL исключены.
3. Перед DML сверить новый reused article `05` с independently captured
   exact-M source control; затем source/stage/target/reused/key/date controls,
   atomic replace существующего `mart.revenue_group_summary_daily` и rerun.

## Rollback и критерий закрытия

Если fresh exact-M control статьи 05 отличается от snapshot общего факта,
разрешён его атомарный refresh существующим reviewed reception loader до
summary replace; это та же подтверждённая логика, объект и scope, без DDL.
Затем разрешён DML в существующей summary table. До commit — `ROLLBACK`;
при ошибке target не меняется. Закрытие требует: нулевые различия ключей и
сумм по article 05, all-five article controls, zero duplicate/contract
violations, passed rerun и измеренную длительность refresh.

## Фактический результат 2026-08-20

Fresh exact-M control статьи 05 первоначально обнаружил один новый дневной
ключ на 245,00; shared reception scope атомарно обновлён тем же reviewed
loader. После обновления source и shared scope совпали: 7 860 ключей и
46 553 069,44, различий 0. Summary refresh использует `05` из общего факта,
только 02/06 остаются direct source branches. В summary 25 339 строк,
duplicate/contract/source-key violations = 0; первый refresh 29,60 с, rerun
29,11 с. Все пять article controls совпали с target.
