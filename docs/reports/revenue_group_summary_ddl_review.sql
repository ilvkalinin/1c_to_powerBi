-- REVIEWED AND APPLIED 2026-08-19 after separate user approval for DDL.
-- Product: mart.revenue_group_summary_daily.
-- Scope: internal current-report articles 02–06 only. Articles 07–13 remain
-- in the existing external Power BI facts and are not copied to PostgreSQL.

BEGIN;

CREATE TABLE mart.revenue_group_summary_daily (
    revenue_date          date          NOT NULL,
    club_id               text          NOT NULL,
    revenue_article_code  text          NOT NULL,
    revenue_amount        numeric(18,2) NOT NULL,
    CONSTRAINT revenue_group_summary_daily_pk
        PRIMARY KEY (revenue_date, club_id, revenue_article_code),
    CONSTRAINT revenue_group_summary_daily_article_ck
        CHECK (revenue_article_code IN (
            '02.ЧЛЕНСТВО',
            '03.ДПФУ (ШТАТ)',
            '04.ДПФУ (АРЕНДА ИП)',
            '05.РЕЦЕПЦИЯ',
            '06.ДРЦ'
        ))
);

COMMENT ON TABLE mart.revenue_group_summary_daily IS
    'Internal daily revenue fact for the current «Свод выручка ГК»: articles 02–06 only.';

COMMIT;

-- Before COMMIT: ROLLBACK.
-- After COMMIT, rollback is a separate approved change. Do not delete the
-- table automatically.
