# Допустимость оставшихся source controls — 2026-08-18

Статус: `DOCUMENTARY_AUDIT_COMPLETE / NO_SOURCE_QUERIES_RUN`.

## Вывод

После сверки [checklist](global_gate_controls_checklist_2026-08-18.md) с
`.agents/report_checkpoint_ledger.tsv` шесть отчётов могут быть выбраны в
будущий отдельный read-only пакет после повторной проверки package gate.
Два отчёта остаются `CLOSED_CHECKPOINT`: наличие старых pending-пунктов в
описании не даёт права запускать их повторно.

| Отчёт | Ledger после аудита | Разрешённый остаток либо причина запрета |
|---|---|---|
| Новички и гостевые визиты | `READY_FOR_NEW_CONTROL` | Только NV-V02/V05/V06/V09: document/contract cardinality, 12 утверждённых ACCUNIQ-кодов и sign rule, границы 0/44/45, booking attribution. Не повторять уже выполненные NV-V01/V03/V04/V07/V08 и SV-097. |
| Отчёт по обращениям | `READY_FOR_NEW_CONTROL` | Только CR-V08 и CR-V11: visit denominator, changes/deletions, rerun и source SLA. Не повторять feedback/HTML/Jivo/status/funnel controls SV-098 и CR-V05D—G. |
| Посещаемость клиентов с долгами | `READY_FOR_NEW_CONTROL` | Только DV-V05/V06/V07: as-of, стабильная классификация current scope и source SLA. Не повторять physical key и document branches SV-099. |
| Работа с посещаемостью | `READY_FOR_NEW_CONTROL` | Только WA-V06 и historical WA-V08: dependency `client_base_daily` и годовой source SLA. Excel шкафчиков/мощности вне scope. |
| Маркетинговая воронка | `READY_FOR_NEW_CONTROL` | Только MF-V08 и MF-V10: exact накопленный трафик и source rerun/SLA. Не повторять task code, joins, states, duration или payment type из SV-101/MF-V04/V06/V07/V07C. |
| Членство для правления | `READY_FOR_NEW_CONTROL` | BR-016 теперь документирован: прежний блокер «один физический ключ ежемесячного платежа» снят. Разрешены только remaining states, non-additive KPI source inputs и source SLA; ошибочный key-control не повторяется. |
| Отчёт по поступлениям | `CLOSED_CHECKPOINT` | SV-096 уже исправил интерпретацию рекарринга. Старые MR-V03—V15 в документации сами по себе не являются новым trigger; повторный source query запрещён без независимого нового evidence или методического решения. |
| Продажа детских пакетов | `CLOSED_CHECKPOINT` | Решение по 38 строкам зафиксировано. Return/state checks остаются артефактами, но новый source query запрещён, пока не появится независимый trigger, прямо записанный в ledger. |

## Граница запуска

Этот аудит не открывает пакет и не разрешает SQL. Перед любым запуском нужно
повторно выполнить `scripts/check_package_selection.sh` для точного состава
пакета; в него могут попасть только шесть строк `READY_FOR_NEW_CONTROL` и
только перечисленные остаточные controls.

Источник: checkpoint ledger, BR-016, `SV-096`, server validation и checklist
2026-08-18.
