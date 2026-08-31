# Требование: единое автоматическое обновление всех витрин

- Дата решения: 2026-08-31
- Статус: `CONFIRMED USER DECISION`
- Execution host: только VM-2
- Scope: все 40 физических витрин проекта

## Требование

Автоматизация не ограничивается `mart.unconfirmed_service_debt_movement`.
Нужно настроить обновление всех 40 физических витрин на VM-2 одним
операционным контуром. Запрещены 40 независимых daily-trigger с одинаковым
стартом и глобальная последовательность по фиксированным 15-минутным slots.

Целевая схема:

1. каждая витрина имеет on-demand job и same-object overlap guard;
2. один VM-2 orchestrator хранит dependency graph и запускает только готовые
   независимые ветки;
3. timeout каждой job основан на измеренном runtime и stop policy, а не на
   общем значении;
4. heavy source plan/transport не выполняются параллельно; лёгкие независимые
   ветки получают ограниченный concurrency budget после измерения;
5. цепочка fail-closed: downstream не запускается после failure dependency;
6. logs/journal не содержат credentials; `.env` остаётся ACL-защищённым на
   VM-2; Power BI и source 1С не изменяются;
7. критический путь должен завершать питающие витрины до BR-014 08:30 МСК.

## Entry evidence

До установки выполнить на VM-2 read-only inventory: реальные relations,
runner/config presence, dependencies, latest acceptance evidence, фактические
runtimes, advisory-lock names и текущие Task Scheduler definitions. Затем
подготовить reviewed DAG/schedule и только после его одобрения устанавливать
общий orchestrator и задачи.

Текущее состояние: `BLOCKED` до появления управляемого remote channel к VM-2.

## Операционная граница — уточнение пользователя 2026-08-31

Установка и запуск задач на VM-2 выполняются оператором в собственной
администраторской PowerShell/RDP-сессии. Агент готовит точные reviewable
команды и интерпретирует их не-секретный вывод; не требуется устанавливать
Codex на VM-2, передавать интерактивный удалённый доступ или пароль. Временный
SSH-channel, подготовленный для альтернативного варианта, удаляется и не
используется.

## Deployment model — уточнение пользователя 2026-08-31

GitHub хранит итоговую versioned версию проекта. VM-2 не получает полный
development checkout: для исполнения нужен только локальный minimal release
bundle (runner/config/SQL/dependencies) в выделенной папке, потому что Windows
Task Scheduler не исполняет Python-код напрямую из GitHub. `.env` не входит в
GitHub или release bundle и создаётся локально на VM-2 после определения
service account и ACL. До публикации финального release проводится audit
локальной ветки: её нельзя публиковать вместе с чужими dirty files.

Подтверждённый deployment root на VM-2:
`C:\Users\a.tolstikov\Desktop\Fitness\_dwh`. В нём размещаются только
`release`, `config`, `logs` и `state`. Плановая task должна запускаться от
`a.tolstikov` либо от service account с явно предоставленными NTFS правами к
этому root; размещение в `C:\Windows\System32` запрещено.
