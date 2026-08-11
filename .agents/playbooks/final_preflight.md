# Playbook: final preflight

Сначала классифицируй ответ: `REPORT_HANDOFF` или `DIRECT_REPLY`.

- Для `REPORT_HANDOFF` запусти `scripts/check_final_gate.sh --report-handoff`.
  Ненулевой код запрещает `final`; продолжай work в commentary. Перед handoff
  выполни audit unresolved questions и приложи contract scope, когда это
  требует reference.
- Для `DIRECT_REPLY` запусти `scripts/check_final_gate.sh --direct-reply`.
  Такой ответ не передаёт результат отчёта, не обещает фоновую работу и может
  отвечать на вопрос, подтверждать команду или фиксировать остановку работы.

`final` без режима запрещён. Полная форма статусов и audit: reference,
«Обязательный протокол финального сообщения».
