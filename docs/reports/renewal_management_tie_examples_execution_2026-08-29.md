# RM-TIE-EXAMPLES-001: PII-free decision examples

Date: 2026-08-29. Status: `DECISION_REQUIRED`.

No client name, phone, e-mail, code, contract ID, interaction ID, target access
or mutation is present in this artifact. Exact source queries are
[`renewal_management_next_tie_examples_2026-08-29.sql`](../source_metadata/validation_sql/renewal_management_next_tie_examples_2026-08-29.sql)
and
[`renewal_management_interaction_tie_examples_2026-08-29.sql`](../source_metadata/validation_sql/renewal_management_interaction_tie_examples_2026-08-29.sql).
The accepted read-only runs took 8.671 seconds and 24.316 seconds respectively.

## Same-client next-contract ties

Each pair contains the same earliest eligible next start date. Current M orders
only by that date, so it gives no rule for choosing either candidate.

| Example | Source end | Same next start | Candidate | Activation | Next end | Term days | Payment | Marked |
|---|---|---|---|---|---|---:|---|---|
| N1 | 2025-07-22 | 2025-07-21 | A | 2025-06-16 | 2026-09-14 | 365 | Paid | no |
| N1 | 2025-07-22 | 2025-07-21 | B | 2025-07-21 | 2025-08-03 | 14 | Free | no |
| N2 | 2025-08-10 | 2025-08-22 | A | 2025-03-24 | 2025-09-20 | 30 | Free | no |
| N2 | 2025-08-10 | 2025-08-22 | B | 2025-08-22 | 2026-08-21 | 365 | Paid | no |
| N3 | 2025-09-12 | 2025-09-13 | A | 2024-05-10 | 2025-10-12 | 30 | Free | no |
| N3 | 2025-09-12 | 2025-09-13 | B | 2025-09-07 | 2026-12-30 | 455 | Paid | no |

Choosing A versus B can change `renewal_type`, the Renew numerator and the
displayed activation/return dates for an expiring-contract row.

## Latest-interaction ties with different visible values

Each pair contains the same maximum eligible timestamp for one client. Current
M uses `ROW_NUMBER()` ordered only by this timestamp.

| Example | Same latest timestamp | Candidate A interaction | Candidate B interaction | Shared funnel stage | Shared failure reason |
|---|---|---|---|---|---|
| I1 | 2025-10-18 14:16:58 | Incoming call | Outgoing call | Refusal | Auto |
| I2 | 2026-02-27 14:57:41 | Outgoing call | Chat | Refusal | Auto |
| I3 | 2024-06-26 11:00:01 | Referral registration | Outgoing call | Refusal | Auto |

Choosing a candidate changes the displayed last-interaction type. Other tied
groups may have identical displayed attributes, but the chosen physical row is
still not deterministic without a secondary order.

## Decision required

The next physical mart must define both rules explicitly:

1. Which field sequence ranks candidates sharing the earliest next start date.
2. Which field sequence ranks interactions sharing the latest timestamp.

No field sequence is inferred from technical identifiers or incidental current
row order.
