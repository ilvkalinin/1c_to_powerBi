# RM-TIE-EXAMPLES-001: authorization record

Date: 2026-08-29.

The user requested examples on which to select the two unresolved BR-018
tie-break behaviors for «Управление продлением».

Scope: one read-only, PII-free source query returning up to three samples for
each proven tie class.  The samples may include only anonymized row labels,
dates, durations, payment category, marked flag, interaction type, funnel
stage and failure reason.  They must not expose client names, phones, email,
codes or physical identifiers.  There is no DDL/DML, target access, transport,
Power BI change or methodological selection in this package.

Closure criterion: preserve the exact query and a concise examples artifact;
leave the report `BLOCKED` until the user chooses both tie-break rules.
