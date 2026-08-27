CREATE SCHEMA IF NOT EXISTS mart;

CREATE TABLE IF NOT EXISTS mart.children_package_sale (
    report_row_id text PRIMARY KEY,
    sale_at timestamp without time zone NOT NULL,
    sale_date date NOT NULL,
    receipt_status_id text NOT NULL,
    source_sale_club_id text,
    source_sale_employee_id text,
    club_id text NOT NULL,
    club_name text,
    membership_id text NOT NULL,
    membership_code text NOT NULL,
    membership_name text NOT NULL,
    membership_purchase_date date NOT NULL,
    membership_activation_date date NOT NULL,
    membership_start_date date NOT NULL,
    membership_end_date date NOT NULL,
    adult_client_id text NOT NULL,
    adult_client_code text NOT NULL,
    adult_client_name text NOT NULL,
    child_client_id text NOT NULL,
    child_client_code text NOT NULL,
    child_client_name text NOT NULL,
    product_id text NOT NULL,
    product_name text NOT NULL,
    package_amount numeric(15, 2) NOT NULL,
    package_amount_without_discount numeric(15, 2) NOT NULL,
    package_count numeric(15, 3) NOT NULL,
    sold_correctly_flag boolean NOT NULL,
    movement_kind text NOT NULL,
    CONSTRAINT children_package_sale_movement_kind_check
        CHECK (movement_kind IN ('Приход', 'Расход')),
    CONSTRAINT children_package_sale_sale_date_check
        CHECK (sale_date = sale_at::date),
    CONSTRAINT children_package_sale_membership_dates_check
        CHECK (membership_end_date > membership_start_date)
);
