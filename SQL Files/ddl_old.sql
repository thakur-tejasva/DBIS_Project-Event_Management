-- Active: 1786963744605@@127.0.0.1@3306@event_management
drop DATABASE if EXISTS event_management;
CREATE DATABASE IF NOT EXISTS event_management;
USE event_management;

CREATE TABLE venue (
    venue_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(150) NOT NULL UNIQUE,
    type VARCHAR(80),
    area DECIMAL(12,2) NOT NULL CHECK (area > 0),
    capacity INT NOT NULL CHECK (capacity > 0),
    rate DECIMAL(12,2) NOT NULL CHECK (rate >= 0),
    description TEXT
);

CREATE TABLE customer (
    customer_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    phone_no VARCHAR(20) NOT NULL
);

CREATE TABLE booking (
    booking_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES customer(customer_id),
    venue_id INT NOT NULL REFERENCES venue(venue_id),
    booking_date DATE NOT NULL,
    booking_status ENUM('ACTIVE', 'CANCELLED') NOT NULL DEFAULT 'ACTIVE',
    paid_till DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (paid_till >= 0),
    feedback TEXT,
    specific_instructions TEXT,
    UNIQUE (booking_id, venue_id, booking_date)
);

CREATE TABLE event_slot (
    slot_id TINYINT PRIMARY KEY,
    slot_name VARCHAR(20) NOT NULL UNIQUE,
    slot_start_time TIME NOT NULL CHECK (slot_start_time >= '00:00:00'),
    slot_end_time TIME NOT NULL CHECK (slot_end_time <= '24:00:00'),
    CHECK (slot_end_time > slot_start_time)
);

INSERT INTO event_slot VALUES
    (1, 'MORNING',   '06:00:00', '12:00:00'),
    (2, 'AFTERNOON', '12:00:00', '17:00:00'),
    (3, 'EVENING',   '17:00:00', '21:00:00'),
    (4, 'NIGHT',     '21:00:00', '24:00:00');

CREATE TABLE booking_slot (
    booking_id INT NOT NULL,
    venue_id INT NOT NULL,
    slot_date DATE NOT NULL,
    slot_id TINYINT NOT NULL REFERENCES event_slot(slot_id),
    PRIMARY KEY (booking_id, slot_id),
    UNIQUE (venue_id, slot_date, slot_id),
    FOREIGN KEY (booking_id, venue_id, slot_date)
        REFERENCES booking(booking_id, venue_id, booking_date)
);

CREATE TABLE service (
    service_id INT AUTO_INCREMENT PRIMARY KEY,
    service_name VARCHAR(150) NOT NULL UNIQUE,
    is_contracted BOOLEAN NOT NULL DEFAULT FALSE CHECK (is_contracted IN (0, 1))
);

CREATE TABLE service_tier (
    tier_id INT AUTO_INCREMENT PRIMARY KEY,
    service_id INT NOT NULL REFERENCES service(service_id),
    tier_name VARCHAR(120) NOT NULL,
    description TEXT,
    unit_cost DECIMAL(12,2) NOT NULL CHECK (unit_cost >= 0),
    UNIQUE (service_id, tier_name)
);

CREATE TABLE booking_services (
    booking_id INT NOT NULL REFERENCES booking(booking_id),
    tier_id INT NOT NULL REFERENCES service_tier(tier_id),
    quantity_booked INT NOT NULL CHECK (quantity_booked > 0),
    actual_quantity INT CHECK (actual_quantity >= 0),
    specific_instructions TEXT,
    PRIMARY KEY (booking_id, tier_id)
);

CREATE TABLE employee (
    employee_id INT AUTO_INCREMENT PRIMARY KEY,
    service_id INT NOT NULL REFERENCES service(service_id),
    name VARCHAR(150) NOT NULL,
    role VARCHAR(100) NOT NULL,
    salary DECIMAL(12,2) NOT NULL CHECK (salary >= 0),
    phone_no VARCHAR(20)
);

CREATE TABLE fiscal_year (
    year SMALLINT PRIMARY KEY,
    start_date DATE NOT NULL UNIQUE,
    end_date DATE NOT NULL UNIQUE,
    CHECK (MONTH(start_date) = 4 AND DAYOFMONTH(start_date) = 1),
    CHECK (YEAR(start_date) = year),
    CHECK (end_date = DATE_ADD(start_date, INTERVAL 1 YEAR) - INTERVAL 1 DAY)
);

CREATE TABLE it_slab (
    fiscal_year SMALLINT NOT NULL REFERENCES fiscal_year(year),
    slab_lower_limit DECIMAL(15,2) NOT NULL CHECK (slab_lower_limit >= 0),
    slab_upper_limit DECIMAL(15,2),
    slab_rate DECIMAL(5,2) NOT NULL CHECK (slab_rate BETWEEN 0 AND 100),
    PRIMARY KEY (fiscal_year, slab_lower_limit),
    CHECK (slab_upper_limit IS NULL OR slab_upper_limit > slab_lower_limit)
);

CREATE TABLE pf_rate (
    fiscal_year SMALLINT PRIMARY KEY REFERENCES fiscal_year(year),
    rate DECIMAL(5,2) NOT NULL CHECK (rate BETWEEN 0 AND 100)
);

CREATE TABLE pay_roll (
    employee_id INT NOT NULL REFERENCES employee(employee_id),
    pay_month DATE NOT NULL CHECK (DAYOFMONTH(pay_month) = 1),
    pay_date DATE NOT NULL,
    fiscal_year SMALLINT NOT NULL REFERENCES fiscal_year(year),
    salary DECIMAL(12,2) NOT NULL CHECK (salary >= 0),
    pf_deduction DECIMAL(12,2) NOT NULL CHECK (pf_deduction >= 0),
    tds DECIMAL(12,2) NOT NULL CHECK (tds >= 0),
    net_salary DECIMAL(12,2) GENERATED ALWAYS AS (salary - pf_deduction - tds) STORED,
    PRIMARY KEY (employee_id, pay_month),
    CHECK (fiscal_year = YEAR(pay_date) - (MONTH(pay_date) < 4)),
    CHECK (salary >= pf_deduction + tds)
);

CREATE VIEW vw_booking_services AS
SELECT bs.*, s.service_name, st.tier_name, st.unit_cost,
       bs.quantity_booked * st.unit_cost AS total_tier_cost
FROM booking_services AS bs
JOIN service_tier AS st ON st.tier_id = bs.tier_id
JOIN service AS s ON s.service_id = st.service_id;

-- Cost = venue rate per slot * booked slots + booked service-tier charges.
-- Sum services separately so multiple slots do not multiply service charges.
CREATE VIEW vw_booking_cost AS
SELECT b.booking_id, COUNT(bs.slot_id) AS slots,
       v.rate * COUNT(bs.slot_id)
       + COALESCE((SELECT SUM(s.total_tier_cost)
                   FROM vw_booking_services AS s
                   WHERE s.booking_id = b.booking_id), 0) AS cost
FROM booking AS b
JOIN venue AS v ON v.venue_id = b.venue_id
LEFT JOIN booking_slot AS bs ON bs.booking_id = b.booking_id
GROUP BY b.booking_id, v.venue_id;

CREATE VIEW vw_booking_details AS
SELECT b.*, c.name AS customer_name, c.phone_no AS customer_phone,
       v.name AS venue_name, v.rate AS venue_rate,
       bill.slots, bill.cost, bill.cost - b.paid_till AS dues,
       CASE WHEN b.paid_till >= bill.cost THEN 'PAID'
            WHEN b.paid_till = 0 THEN 'PENDING'
            ELSE 'PARTIAL' END AS payment_status
FROM booking AS b
JOIN customer AS c ON c.customer_id = b.customer_id
JOIN venue AS v ON v.venue_id = b.venue_id
JOIN vw_booking_cost AS bill ON bill.booking_id = b.booking_id;

CREATE VIEW vw_monthly_revenue AS
SELECT YEAR(booking_date) AS year, MONTH(booking_date) AS month,
       COUNT(*) AS booking_count, SUM(cost) AS revenue
FROM vw_booking_details
WHERE booking_status = 'ACTIVE'
GROUP BY YEAR(booking_date), MONTH(booking_date);

-- Project model: annualize monthly salary, sum progressive slab tax, divide by 12.
-- No rebate/cess. Adjacent slabs share boundaries; the final upper limit is NULL.
CREATE VIEW vw_payroll_summary AS
SELECT p.*, e.name AS employee_name, e.role,
       p.salary * 12 AS annual_salary,
       ROUND(p.salary * r.rate / 100, 2) AS calculated_pf,
       (SELECT ROUND(SUM(
            GREATEST(LEAST(p.salary * 12,
                           COALESCE(s.slab_upper_limit, p.salary * 12))
                     - s.slab_lower_limit, 0) * s.slab_rate / 100
        ) / 12, 2)
        FROM it_slab AS s
        WHERE s.fiscal_year = p.fiscal_year) AS calculated_monthly_tds
FROM pay_roll AS p
JOIN employee AS e ON e.employee_id = p.employee_id
LEFT JOIN pf_rate AS r ON r.fiscal_year = p.fiscal_year;
