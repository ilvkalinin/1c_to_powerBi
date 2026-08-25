# Playbook: STAGE_1_LOCAL_ANALYSIS

Разрешены только локальный анализ материалов, requirements, query review,
mapping, reuse review и подготовка SQL как `VALIDATION_PENDING` /
`NOT_EXECUTED — ожидается подключение к корпоративной сети`.

Внутри согласованного пакета самостоятельно выполни все разрешённые анализ,
mapping, reuse review и подготовку проверок; не согласовывай каждый документ,
вывод или SQL-черновик отдельно.

Запрещены любые подключения к PostgreSQL/1С, ping, schema discovery, SQL,
`EXPLAIN`, серверные MCP, DDL/DML, объекты витрин и `postgres_engineer`.
Переход — только после явного сообщения пользователя о корпоративной сети и
разрешения на server validation.
