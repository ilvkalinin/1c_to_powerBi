# Data contract: `mart.visit_client_day`

Статус: `IMPLEMENTED / initial BR-003 load validated — S3-VISIT-CLIENT-DAY-001`.

| Parameter | Contract |
|---|---|
| Grain / key | one `visit_date × club_id × client_key`; primary key of all three columns |
| Refresh | atomic full BR-003 rebuild; no watermark or schedule in this package |
| Power BI | Import later; shared Calendar and Clubs filter `1:*`, single direction |
| Date role | `visit_date` active calendar date |
| Additivity | flags are client-day attributes, never summed as visits; DAX uses `DISTINCTCOUNT(client_key)` after flag filtering |
| Visibility | `client_key` and `club_id` technical IDs hidden; booleans only support measures/slices |

The fact contains `visit_date date`, `club_id text`, `client_key text` and the
seven NOT NULL booleans `has_visit`, `has_member_visit`, `has_guest_visit`,
`has_vip_visit`, `has_drc_visit`, `has_after_school_visit`,
`has_umnyashki_visit`. It contains no PII, contracts, source document IDs,
services, employee data or raw visits.

`has_coupon` and `has_paid_service` are deliberately absent. Current PBIT
models keep coupons and DPFU as independent facts and combine their measures
arithmetically in DAX. Group lessons and IP are likewise independent facts.
There are no fact-to-fact or many-to-many relationships.
