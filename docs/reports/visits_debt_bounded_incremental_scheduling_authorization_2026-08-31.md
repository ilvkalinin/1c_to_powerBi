# Авторизация operations: расписание bounded refresh движений долга

- Пакет: `visits_debt_bounded_incremental_scheduling_2026-08-31`
- Объект: `mart.unconfirmed_service_debt_movement`
- Основание: пользователь подтвердил отдельный scheduling-пакет.

## Scope

1. Создать PowerShell wrapper для отдельного bounded runner: безопасный
   project/python path через environment, timestamped log без credentials,
   ненулевой exit при любой ошибке и Windows Application Event об ошибке.
2. Создать Windows Task Scheduler XML как on-demand job без собственного
   trigger: `IgnoreNew` защищает только этот объект, `PT5M` timeout рассчитан
   по измеренным 92.673 s, ненулевой LastTaskResult сохраняет failure.
3. Текущий full loader, Power BI, source 1С и SQL-методика не меняются.
4. Проверить wrapper локально статически. Установить задачу на VM-2 только если
   текущая среда имеет доказанный credential-safe remote-management channel и
   operator authority; иначе сохранить точный handoff и статус `BLOCKED`, не
   заявляя внешнюю установку.

После замечания пользователя одиночный daily trigger исключён: 40 витрин
нельзя планировать как последовательные 15-минутные slots или одновременно.
Время старта определит отдельный project-wide orchestrator с dependency graph,
измеренными runtime и ограниченной параллельностью лёгких веток.

## Closure

Артефакты проходят static checks; если доступна authority — on-demand задача
создана и её definition/read-back проверены без немедленного второго DML refresh. Если
authority отсутствует, пакет закрывается документированным external-install
blocker и готовой операторской командой.
