-- Active: 1786963744605@@127.0.0.1@3306@event_management
DROP DATABASE IF EXISTS event_management;
CREATE DATABASE event_management;
USE event_management;
CREATE TABLE venue (
    venue_id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(150) NOT NULL UNIQUE,
    type VARCHAR(80) NULL,
    area DECIMAL(12,2) UNSIGNED NOT NULL CHECK (area > 0),
    capacity INT UNSIGNED NOT NULL CHECK (capacity > 0),
    rate DECIMAL(12,2) UNSIGNED NOT NULL CHECK (rate >= 0),
    description TEXT NULL,
    KEY idx_venue_type (type)
);

CREATE TABLE customer (
    customer_id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    phone_no VARCHAR(20) NOT NULL,
    KEY idx_customer_name (name),
    KEY idx_customer_phone (phone_no)
);

CREATE TABLE booking (
    booking_id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    customer_id INT UNSIGNED NOT NULL REFERENCES customer(customer_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    venue_id INT UNSIGNED NOT NULL REFERENCES venue(venue_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    booking_date DATE NOT NULL,
    feedback TEXT NULL,
    cost DECIMAL(12,2) UNSIGNED NOT NULL CHECK (cost >= 0),
    paid_till DECIMAL(12,2) UNSIGNED NOT NULL DEFAULT 0.00,
    dues DECIMAL(12,2) GENERATED ALWAYS AS (cost - paid_till) STORED,
    payment_status ENUM('PENDING', 'PARTIAL', 'PAID', 'CANCELLED') NOT NULL DEFAULT 'PENDING',
    specific_instructions TEXT NULL,
    UNIQUE KEY uq_booking_details (booking_id, venue_id, booking_date),
    KEY idx_booking_customer (customer_id),
    KEY idx_booking_venue (venue_id),
    KEY idx_booking_date (booking_date),
    KEY idx_booking_payment_status (payment_status),
    CHECK (paid_till <= cost),
    CHECK ((payment_status = 'PAID' AND paid_till = cost) OR payment_status <> 'PAID'),
    CHECK ((payment_status = 'PARTIAL' AND paid_till > 0 AND paid_till < cost) OR payment_status <> 'PARTIAL')
);

CREATE TABLE event_slot (
    slot_id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
    slot_name VARCHAR(20) NOT NULL UNIQUE,
    slot_start_time TIME NOT NULL,
    slot_end_time TIME NOT NULL,
    CHECK (slot_end_time > slot_start_time)
);

INSERT INTO event_slot (slot_id, slot_name, slot_start_time, slot_end_time)
VALUES
    (1, 'MORNING', '06:00:00', '12:00:00'),
    (2, 'AFTERNOON', '12:00:00', '17:00:00'),
    (3, 'EVENING', '17:00:00', '21:00:00'),
    (4, 'NIGHT', '21:00:00', '23:59:59');

CREATE TABLE booking_slot (
    booking_slot_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    booking_id INT UNSIGNED NOT NULL,
    venue_id INT UNSIGNED NOT NULL,
    slot_date DATE NOT NULL,
    slot_id TINYINT UNSIGNED NOT NULL,
    UNIQUE KEY uq_booking_slot_per_booking (booking_id, slot_id),
    UNIQUE KEY uq_venue_slot_date (venue_id, slot_date, slot_id),
    KEY idx_booking_slot_booking (booking_id),
    KEY idx_booking_slot_date (slot_date),
    CONSTRAINT fk_booking_slot_booking
        FOREIGN KEY (booking_id, venue_id, slot_date)
        REFERENCES booking (booking_id, venue_id, booking_date)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_booking_slot_slot
        FOREIGN KEY (slot_id)
        REFERENCES event_slot (slot_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE service (
    service_id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    service_name VARCHAR(150) NOT NULL UNIQUE,
    is_contracted BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE service_tier (
    tier_id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    service_id INT UNSIGNED NOT NULL REFERENCES service(service_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    tier_name VARCHAR(120) NOT NULL,
    description TEXT NULL,
    unit_cost DECIMAL(12,2) UNSIGNED NOT NULL CHECK (unit_cost >= 0),
    UNIQUE KEY uq_service_tier_name (service_id, tier_name),
    KEY idx_service_tier_service (service_id)
);

CREATE TABLE booking_services (
    booking_id INT UNSIGNED NOT NULL REFERENCES booking(booking_id) ON UPDATE CASCADE ON DELETE CASCADE,
    tier_id INT UNSIGNED NOT NULL REFERENCES service_tier(tier_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    quantity_booked INT UNSIGNED NOT NULL CHECK (quantity_booked > 0),
    actual_quantity INT UNSIGNED NOT NULL DEFAULT 0,
    specific_instructions TEXT NULL,
    PRIMARY KEY (booking_id, tier_id),
    KEY idx_booking_services_tier (tier_id),
    CHECK (actual_quantity <= quantity_booked)
);

CREATE TABLE employee (
    employee_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    service_id INT UNSIGNED NOT NULL REFERENCES service(service_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    name VARCHAR(150) NOT NULL,
    role VARCHAR(100) NOT NULL,
    salary DECIMAL(12,2) UNSIGNED NOT NULL CHECK (salary >= 0),
    phone_no VARCHAR(20) NULL,
    KEY idx_employee_service (service_id),
    KEY idx_employee_name (name),
    KEY idx_employee_phone (phone_no)
);

CREATE TABLE fiscal_year (
    year SMALLINT UNSIGNED NOT NULL PRIMARY KEY,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    UNIQUE KEY uq_fiscal_year_dates (start_date, end_date),
    CHECK (end_date >= start_date),
    CHECK (end_date = DATE_ADD(start_date, INTERVAL 1 YEAR) - INTERVAL 1 DAY)
);

CREATE TABLE it_slab (
    fiscal_year SMALLINT UNSIGNED NOT NULL REFERENCES fiscal_year(year) ON UPDATE CASCADE ON DELETE CASCADE,
    slab_lower_limit DECIMAL(15,2) UNSIGNED NOT NULL CHECK (slab_lower_limit >= 0),
    slab_upper_limit DECIMAL(15,2) UNSIGNED NULL,
    slab_rate DECIMAL(7,4) UNSIGNED NOT NULL CHECK (slab_rate >= 0 AND slab_rate <= 100),
    PRIMARY KEY (fiscal_year, slab_lower_limit),
    CHECK (slab_upper_limit IS NULL OR slab_upper_limit >= slab_lower_limit)
);

CREATE TABLE pf_rate (
    fiscal_year SMALLINT UNSIGNED NOT NULL REFERENCES fiscal_year(year) ON UPDATE CASCADE ON DELETE CASCADE,
    rate DECIMAL(7,4) UNSIGNED NOT NULL CHECK (rate >= 0 AND rate <= 100),
    PRIMARY KEY (fiscal_year)
);

CREATE TABLE pay_roll (
    employee_id BIGINT UNSIGNED NOT NULL REFERENCES employee(employee_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    pay_date DATE NOT NULL,
    fiscal_year SMALLINT UNSIGNED NOT NULL REFERENCES fiscal_year(year) ON UPDATE CASCADE ON DELETE RESTRICT,
    slab_lower_limit DECIMAL(15,2) UNSIGNED NOT NULL,
    salary DECIMAL(12,2) UNSIGNED NOT NULL CHECK (salary >= 0),
    pf_deduction DECIMAL(12,2) UNSIGNED NOT NULL DEFAULT 0.00 CHECK (pf_deduction >= 0),
    tds DECIMAL(12,2) UNSIGNED NOT NULL DEFAULT 0.00 CHECK (tds >= 0),
    net_salary DECIMAL(12,2) GENERATED ALWAYS AS (salary - pf_deduction - tds) STORED,
    PRIMARY KEY (employee_id, pay_date),
    KEY idx_payroll_fiscal_year (fiscal_year),
    KEY idx_payroll_slab (fiscal_year, slab_lower_limit),
    KEY idx_payroll_pay_date (pay_date),
    CHECK (salary >= pf_deduction + tds),
    CONSTRAINT fk_payroll_it_slab FOREIGN KEY (fiscal_year, slab_lower_limit)
        REFERENCES it_slab(fiscal_year, slab_lower_limit)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE VIEW vw_booking_details AS
SELECT
    b.booking_id,
    b.booking_date,
    c.customer_id,
    c.name AS customer_name,
    c.phone_no AS customer_phone,
    v.venue_id,
    v.name AS venue_name,
    v.type AS venue_type,
    v.area AS venue_area,
    v.capacity AS venue_capacity,
    v.rate AS venue_rate,
    COALESCE((SELECT COUNT(*) FROM booking_slot AS bs WHERE bs.booking_id = b.booking_id), 0) AS slots,
    b.cost,
    b.paid_till,
    b.dues,
    b.payment_status,
    b.feedback,
    b.specific_instructions
FROM booking AS b
JOIN customer AS c ON c.customer_id = b.customer_id
JOIN venue AS v ON v.venue_id = b.venue_id;

CREATE VIEW vw_booking_services AS
SELECT
    bs.booking_id,
    bs.tier_id,
    s.service_id,
    s.service_name,
    st.tier_name,
    st.unit_cost,
    bs.quantity_booked,
    bs.actual_quantity,
    (bs.actual_quantity * st.unit_cost) AS total_tier_cost,
    bs.specific_instructions
FROM booking_services AS bs
JOIN service_tier AS st ON st.tier_id = bs.tier_id
JOIN service AS s ON s.service_id = st.service_id;

CREATE VIEW vw_monthly_revenue AS
SELECT
    fy.year,
    MONTH(b.booking_date) AS month,
    COUNT(*) AS booking_count,
    COALESCE(SUM(b.cost), 0.00) AS revenue
FROM booking AS b
JOIN fiscal_year AS fy ON b.booking_date BETWEEN fy.start_date AND fy.end_date
WHERE b.payment_status <> 'CANCELLED'
GROUP BY fy.year, MONTH(b.booking_date);

CREATE VIEW vw_payroll_summary AS
SELECT
    p.employee_id,
    e.name AS employee_name,
    e.role,
    p.pay_date,
    p.fiscal_year,
    p.salary AS monthly_salary,
    p.salary * 12 AS annual_salary,
    s.slab_lower_limit,
    s.slab_upper_limit,
    s.slab_rate,
    CASE
        WHEN p.salary * 12 <= s.slab_lower_limit THEN 0
        WHEN s.slab_upper_limit IS NULL THEN (((p.salary * 12) - s.slab_lower_limit) * s.slab_rate / 100) / 12
        ELSE ((LEAST(p.salary * 12, s.slab_upper_limit) - s.slab_lower_limit) * s.slab_rate / 100) / 12
    END AS monthly_tds_by_slab,
    p.pf_deduction,
    p.tds,
    p.net_salary
FROM pay_roll AS p
JOIN employee AS e ON e.employee_id = p.employee_id
JOIN it_slab AS s
  ON s.fiscal_year = p.fiscal_year
 AND p.salary * 12 >= s.slab_lower_limit
 AND (s.slab_upper_limit IS NULL OR p.salary * 12 < s.slab_upper_limit);
