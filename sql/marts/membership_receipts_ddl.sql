-- APPLIED only after explicit user approval on 2026-08-19.
-- Implements the two shared products for «Отчёт по поступлениям» and
-- «Членство для правления». No board-only fact or `___Итого по сети` cache.
-- Rollback before COMMIT: ROLLBACK.
-- Post-commit rollback is a separate approved change and is deliberately not automated.

BEGIN;

CREATE TABLE mart.membership_receipt_movement (
    source_kind                     text    NOT NULL,
    source_object                   text,
    receipt_date                    date    NOT NULL,
    source_group_recorder_id        text,
    source_group_line_no            integer,
    contract_id                     text,
    client_key                      text,
    accounting_analytics_text       text,
    payment_period                  integer,
    payment_type                    text    NOT NULL,
    movement_kind                   smallint,
    recorder_type                   text,
    movement_club_id                text,
    access_club_id                  text,
    sales_point_club_id             text,
    reporting_club_id               text    NOT NULL,
    manager_id                      text,
    product_id                      text,
    source_product_name             text,
    source_product_freeze_days      numeric,
    contract_activation_date        date,
    contract_start_date             date,
    contract_end_date               date,
    contract_term_days              numeric,
    source_stage_id                 text,
    source_stage                    text,
    super_stage                     text    NOT NULL,
    payment_source                  text,
    product_age_category            text,
    purchase_type                   text,
    purchase_type_id                text,
    membership_kind                 text,
    membership_kind_id              text,
    club_access_type                text,
    club_access_type_id             text,
    access_time_type                text,
    access_zone                     text,
    amount_raw                      numeric NOT NULL,
    amount_signed                   numeric NOT NULL,
    co_access_amount                numeric NOT NULL,
    receipt_amount_net              numeric NOT NULL,
    service_group                   text,
    source_movement_count           bigint  NOT NULL,
    CONSTRAINT membership_receipt_movement_source_kind_ck
        CHECK (source_kind IN ('ordinary_advance', 'towel_advance', 'membership_service')),
    CONSTRAINT membership_receipt_movement_payment_type_ck
        CHECK (payment_type IN ('Предоплата', 'Рекарринг', 'Услуга')),
    CONSTRAINT membership_receipt_movement_service_source_key_ck
        CHECK (
            (source_kind = 'membership_service'
             AND source_group_recorder_id IS NOT NULL
             AND source_group_line_no IS NOT NULL)
            OR
            (source_kind <> 'membership_service'
             AND source_group_recorder_id IS NULL
             AND source_group_line_no IS NULL)
        ),
    CONSTRAINT membership_receipt_movement_source_count_ck
        CHECK (source_movement_count > 0),
    CONSTRAINT membership_receipt_movement_current_m_group_uq
        UNIQUE NULLS NOT DISTINCT (
            source_kind, receipt_date, source_group_recorder_id,
            source_group_line_no, contract_id, accounting_analytics_text,
            payment_type, client_key, access_club_id, sales_point_club_id,
            contract_activation_date, contract_start_date, contract_end_date,
            source_stage_id, source_product_name, source_product_freeze_days,
            product_id, contract_term_days, purchase_type_id,
            membership_kind_id, club_access_type_id, source_object
        )
);

CREATE TABLE mart.membership_contract_kpi_unit (
    kpi_unit_key                    text    PRIMARY KEY,
    kpi_unit_kind                   text    NOT NULL,
    metric_date                     date,
    contract_id                     text    NOT NULL,
    client_key                      text,
    payment_period                  integer,
    access_club_id                  text,
    sales_point_club_id             text,
    manager_id                      text,
    product_id                      text,
    contract_activation_date        date,
    contract_start_date             date,
    contract_end_date               date,
    contract_term_days              numeric,
    free_freeze_before_activation_days numeric NOT NULL,
    effective_duration_days         numeric,
    source_stage                    text,
    super_stage                     text    NOT NULL,
    payment_type                    text    NOT NULL,
    payment_source                  text,
    product_age_category            text,
    purchase_type                   text,
    membership_kind                 text,
    club_access_type                text,
    access_time_type                text,
    access_zone                     text,
    list_contract_price             numeric,
    calculation_price               numeric,
    calculation_mode                text    NOT NULL,
    source_movement_count           bigint  NOT NULL,
    CONSTRAINT membership_contract_kpi_unit_kind_ck
        CHECK (kpi_unit_kind IN ('prepayment_contract', 'recurring_payment')),
    CONSTRAINT membership_contract_kpi_unit_payment_type_ck
        CHECK (payment_type IN ('Предоплата', 'Рекарринг')),
    CONSTRAINT membership_contract_kpi_unit_period_ck
        CHECK (
            (kpi_unit_kind = 'recurring_payment' AND payment_period IS NOT NULL)
            OR (kpi_unit_kind = 'prepayment_contract' AND payment_period IS NULL)
        ),
    CONSTRAINT membership_contract_kpi_unit_source_count_ck
        CHECK (source_movement_count > 0)
);

COMMIT;
