# Авторизация compatibility decision: «Воронка лиды фитнес»

Статус: `CONFIRMED`.

24.08.2026 пользователь подтвердил воспроизведение текущего поведения Power
BI для услуги: прямые многозначные source services не дедуплицируются, а при
отсутствии прямой услуги fallback использует DAX `MIN` на самой ранней дате
записи в current window.

Разрешённый scope: зафиксировать это business decision в mapping, ADR,
contract и admission plan; определить, что одна task-row не содержит
придуманного единственного `service_name`, а future service consumer получает
отдельный multivalued bridge. Пакет documentation-only: без source/VM access,
DDL/DML, объектов, Power BI/M/DAX/PBIT, Excel, schedule или implementation.

Критерий закрытия: решение и точная граница task fact/service bridge
согласованно зафиксированы, а следующий runnable-admission scope определён
без неявной дедупликации.
