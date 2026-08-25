# Решение: тип «Дети» для всех child packages в `mart.client_base_daily`

## Подтверждённый факт

S3-CBD-PKG-001 включил BR-037 child-package branch и успешно прошёл atomic
source/stage/target reconciliation. Среди 18 429 valid `договор × ребёнок`
ranges 95 имеют фактический возраст ровно 14 на package start (31 027
client-days BR-003). Пользователь подтвердил правило BR-038: все child packages
входят с типом `Дети`, включая ranges с фактическим возрастом 14. Текущий
physical check допускает `Дети` только при `age_years < 14`, а отдельного
package/source type среди семи колонок нет.

## Принятое решение

Сохранить текущий grain и семь target columns, без source-type колонки и без
изменения Power BI. Extract помечает BR-037 package-interval как `Дети`
независимо от фактического возраста и вычитает этот interval из обычного
membership-set до агрегации: один client-day не может быть одновременно package
и membership. `age_years` остаётся фактическим.

Минимальная DDL-миграция расширяет `client_base_daily_age_ck`: `Дети` допустимы
при любом фактическом возрасте, а обычные `Юниоры`/`Взрослые` остаются в своих
возрастных границах. Так как physical fact намеренно не хранит source type,
происхождение `Дети` с возрастом 14+ проверяется independent source-side
reconciliation: такие client-days могут возникать только из BR-037/BR-038
package-ветви. Migration и rollback выполняются внутри одной атомарной target
transaction с rebuild.

## Состояние текущего пакета

Business decision closed. Текущий package выполняет reviewed DDL, full rebuild,
source/stage/target reconciliation и atomic rerun; Power BI остаётся вне scope
по BR-036.
