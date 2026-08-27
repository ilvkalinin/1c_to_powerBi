-- REVIEWED DDL — execute only through scripts/load_employee_activity_interval.py.
CREATE SCHEMA IF NOT EXISTS mart;

CREATE TABLE mart.employee_activity_interval (
    activity_event_key text PRIMARY KEY,
    activity_date date NOT NULL,
    club_id text NOT NULL,
    employee_id text NOT NULL,
    activity_id text,
    service_id text,
    room_id text,
    activity_kind text NOT NULL,
    start_at timestamp without time zone NOT NULL,
    end_at timestamp without time zone NOT NULL,
    duration_minutes numeric NOT NULL,
    payment_kind text NOT NULL,
    CONSTRAINT employee_activity_interval_kind_check
        CHECK (activity_kind IN ('TRAINING', 'DUTY', 'COUPON_1', 'COUPON_2')),
    CONSTRAINT employee_activity_interval_payment_check
        CHECK (payment_kind IN ('Платно', 'Бесплатно', 'Дежурство')),
    CONSTRAINT employee_activity_interval_bounds_check
        CHECK (end_at > start_at),
    CONSTRAINT employee_activity_interval_duration_check
        CHECK (duration_minutes >= 0),
    CONSTRAINT employee_activity_interval_duty_shape_check
        CHECK ((activity_kind = 'DUTY') = (payment_kind = 'Дежурство')),
    CONSTRAINT employee_activity_interval_coupon_shape_check
        CHECK (activity_kind NOT IN ('COUPON_1', 'COUPON_2')
               OR payment_kind = 'Бесплатно')
);

REVOKE ALL ON mart.employee_activity_interval FROM PUBLIC;
