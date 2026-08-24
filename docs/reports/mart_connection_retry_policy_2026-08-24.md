# Единая политика переподключения загрузчиков витрин

Статус: `IMPLEMENTED / VERIFIED`.

Дата: 2026-08-24.

## Правило

Каждый production `load_*.py` делает первоначальную попытку соединения и
затем не более пяти повторов только при `psycopg.OperationalError`.
Телеметрия содержит endpoint, номер повтора и задержку. Ошибки
authentication/role/database-selection (`28*`, `3D*`), SQL, reconciliation и
данных не повторяются и остаются fail-closed.

Повтор относится к открытию нового source/target session. Он не превращает
неудавшийся DML в частичный повтор: атомарность транзакции и rollback каждого
конкретного loader остаются прежними. `refresh_revenue_chain.py` не открывает
соединений сам, а запускает только проверяемые stage-loader’ы.

## Реализация

- общий helper: `scripts/mart_connection.py`;
- статический fail-closed gate: `scripts/check_connection_retry_policy.py`;
- 17 runner’ов проверяются: все `scripts/load_*.py` и
  `scripts/refresh_revenue_chain.py`.

CRM сохраняет свой 15-секундный интервал и отдельный retry transaction для
bounded target COPY, но количество admission-attempts приведено к той же
семантике: initial attempt + 5 retries. Fitness-leads уже использовал эту
семантику и включён в проверку.

## Проверки

| Check | Expected | Actual | Status |
|---|---|---|---|
| unit-like transient admission | 5 `OperationalError`, затем success на шестой попытке | helper выполнил 6 attempts и вернул соединение | PASS |
| import safety | `--help` каждого runner не выполняет DML и не ломается на import | 17 из 17 | PASS |
| static coverage | ни один runner не обходит retry policy | 17 из 17 | PASS |

Ни один существующий mart не перезагружался этой операционной доработкой.
