-- Re-runnable starter catalogue. Existing names and user changes are preserved.
USE event_management;

INSERT IGNORE INTO venue (name, type, area, capacity, rate, description) VALUES
    ('Lotus Garden', 'Garden', 12000.00, 500, 65000.00, 'Open garden venue; area in square feet.'),
    ('Peacock Banquet Hall', 'Banquet Hall', 7000.00, 250, 42000.00, 'Indoor banquet hall; area in square feet.'),
    ('Mango Courtyard', 'Lawn', 16000.00, 800, 85000.00, 'Large lawn venue; area in square feet.');

INSERT IGNORE INTO service (service_name, is_contracted) VALUES
    ('Catering', FALSE),
    ('Floral Decoration', FALSE),
    ('Sound and Lighting', TRUE),
    ('Photography', TRUE);

INSERT IGNORE INTO service_tier (service_id, tier_name, description, unit_cost)
SELECT service_id, 'Vegetarian Plate', 'Per guest plate', 650.00
FROM service WHERE service_name = 'Catering';
INSERT IGNORE INTO service_tier (service_id, tier_name, description, unit_cost)
SELECT service_id, 'Non-Vegetarian Plate', 'Per guest plate', 850.00
FROM service WHERE service_name = 'Catering';
INSERT IGNORE INTO service_tier (service_id, tier_name, description, unit_cost)
SELECT service_id, 'Children Plate', 'Per guest plate', 400.00
FROM service WHERE service_name = 'Catering';
INSERT IGNORE INTO service_tier (service_id, tier_name, description, unit_cost)
SELECT service_id, 'Floral Stage Package', 'One package per event', 32000.00
FROM service WHERE service_name = 'Floral Decoration';
INSERT IGNORE INTO service_tier (service_id, tier_name, description, unit_cost)
SELECT service_id, 'Table Centrepiece', 'Per table', 1800.00
FROM service WHERE service_name = 'Floral Decoration';
INSERT IGNORE INTO service_tier (service_id, tier_name, description, unit_cost)
SELECT service_id, 'Event Sound and Lighting', 'One package per event', 18000.00
FROM service WHERE service_name = 'Sound and Lighting';
INSERT IGNORE INTO service_tier (service_id, tier_name, description, unit_cost)
SELECT service_id, 'Wireless Microphone', 'Per microphone', 1000.00
FROM service WHERE service_name = 'Sound and Lighting';
INSERT IGNORE INTO service_tier (service_id, tier_name, description, unit_cost)
SELECT service_id, 'Event Photography Package', 'One package per event', 28000.00
FROM service WHERE service_name = 'Photography';

-- Clearly marked demo staff make the employee and tax-estimate screens useful
-- immediately. The NOT EXISTS checks keep repeated setup runs from duplicating them.
INSERT INTO employee (service_id, name, role, salary, phone_no)
SELECT s.service_id, 'Demo Chef', 'Head Chef', 60000.00, NULL
FROM service s
WHERE s.service_name = 'Catering'
  AND NOT EXISTS (SELECT 1 FROM employee e
                  WHERE e.service_id = s.service_id AND e.name = 'Demo Chef');
INSERT INTO employee (service_id, name, role, salary, phone_no)
SELECT s.service_id, 'Demo Decorator', 'Floral Designer', 45000.00, NULL
FROM service s
WHERE s.service_name = 'Floral Decoration'
  AND NOT EXISTS (SELECT 1 FROM employee e
                  WHERE e.service_id = s.service_id AND e.name = 'Demo Decorator');
INSERT INTO employee (service_id, name, role, salary, phone_no)
SELECT s.service_id, 'Demo Sound Operator', 'AV Technician', 42000.00, NULL
FROM service s
WHERE s.service_name = 'Sound and Lighting'
  AND NOT EXISTS (SELECT 1 FROM employee e
                  WHERE e.service_id = s.service_id AND e.name = 'Demo Sound Operator');

-- Tax Year 2026-27 (the first year in the project seed schedule).
-- 12% is the employee-side EPF contribution used by this salary-only demo.
INSERT IGNORE INTO fiscal_year (year, start_date, end_date)
VALUES (2026, '2026-04-01', '2027-03-31');
INSERT IGNORE INTO pf_rate (fiscal_year, rate) VALUES (2026, 12.00);
INSERT IGNORE INTO it_slab (fiscal_year, slab_lower_limit, slab_upper_limit, slab_rate) VALUES
    (2026,        0.00,  400000.00,  0.00),
    (2026,   400000.00,  800000.00,  5.00),
    (2026,   800000.00, 1200000.00, 10.00),
    (2026,  1200000.00, 1600000.00, 15.00),
    (2026,  1600000.00, 2000000.00, 20.00),
    (2026,  2000000.00, 2400000.00, 25.00),
    (2026,  2400000.00,       NULL, 30.00);

-- Demo customers use clearly fake contact identifiers and are safe to re-run.
INSERT INTO customer (name, phone_no)
SELECT 'Demo Customer - Aarav and Meera', 'DEMO-CUST-2026-001'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM customer WHERE phone_no='DEMO-CUST-2026-001');
INSERT INTO customer (name, phone_no)
SELECT 'Demo Customer - Nisha Patel', 'DEMO-CUST-2026-002'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM customer WHERE phone_no='DEMO-CUST-2026-002');
INSERT INTO customer (name, phone_no)
SELECT 'Demo Customer - Aditya Family', 'DEMO-CUST-2026-003'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM customer WHERE phone_no='DEMO-CUST-2026-003');
INSERT INTO customer (name, phone_no)
SELECT 'Demo Customer - Rhea Sharma', 'DEMO-CUST-2026-004'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM customer WHERE phone_no='DEMO-CUST-2026-004');

-- Four future sample events show single- and multi-slot bookings, several
-- service tiers, and pending, partial, and paid payment states.
SET @demo_booking_1 = (SELECT b.booking_id FROM booking b
    JOIN customer c ON c.customer_id=b.customer_id
    WHERE c.phone_no='DEMO-CUST-2026-001'
      AND b.specific_instructions='DEMO SAMPLE: Wedding reception at Peacock Banquet Hall'
    ORDER BY b.booking_id LIMIT 1);
INSERT INTO booking (customer_id,venue_id,booking_date,specific_instructions)
SELECT c.customer_id,v.venue_id,'2026-12-12',
       'DEMO SAMPLE: Wedding reception at Peacock Banquet Hall'
FROM customer c JOIN venue v ON v.name='Peacock Banquet Hall'
WHERE c.phone_no='DEMO-CUST-2026-001' AND @demo_booking_1 IS NULL;
SET @demo_booking_1 = (SELECT b.booking_id FROM booking b
    JOIN customer c ON c.customer_id=b.customer_id
    WHERE c.phone_no='DEMO-CUST-2026-001'
      AND b.specific_instructions='DEMO SAMPLE: Wedding reception at Peacock Banquet Hall'
    ORDER BY b.booking_id LIMIT 1);

SET @demo_booking_2 = (SELECT b.booking_id FROM booking b
    JOIN customer c ON c.customer_id=b.customer_id
    WHERE c.phone_no='DEMO-CUST-2026-002'
      AND b.specific_instructions='DEMO SAMPLE: Garden wedding at Lotus Garden'
    ORDER BY b.booking_id LIMIT 1);
INSERT INTO booking (customer_id,venue_id,booking_date,specific_instructions)
SELECT c.customer_id,v.venue_id,'2027-01-23',
       'DEMO SAMPLE: Garden wedding at Lotus Garden'
FROM customer c JOIN venue v ON v.name='Lotus Garden'
WHERE c.phone_no='DEMO-CUST-2026-002' AND @demo_booking_2 IS NULL;
SET @demo_booking_2 = (SELECT b.booking_id FROM booking b
    JOIN customer c ON c.customer_id=b.customer_id
    WHERE c.phone_no='DEMO-CUST-2026-002'
      AND b.specific_instructions='DEMO SAMPLE: Garden wedding at Lotus Garden'
    ORDER BY b.booking_id LIMIT 1);

SET @demo_booking_3 = (SELECT b.booking_id FROM booking b
    JOIN customer c ON c.customer_id=b.customer_id
    WHERE c.phone_no='DEMO-CUST-2026-003'
      AND b.specific_instructions='DEMO SAMPLE: Family celebration at Mango Courtyard'
    ORDER BY b.booking_id LIMIT 1);
INSERT INTO booking (customer_id,venue_id,booking_date,specific_instructions)
SELECT c.customer_id,v.venue_id,'2027-02-14',
       'DEMO SAMPLE: Family celebration at Mango Courtyard'
FROM customer c JOIN venue v ON v.name='Mango Courtyard'
WHERE c.phone_no='DEMO-CUST-2026-003' AND @demo_booking_3 IS NULL;
SET @demo_booking_3 = (SELECT b.booking_id FROM booking b
    JOIN customer c ON c.customer_id=b.customer_id
    WHERE c.phone_no='DEMO-CUST-2026-003'
      AND b.specific_instructions='DEMO SAMPLE: Family celebration at Mango Courtyard'
    ORDER BY b.booking_id LIMIT 1);

SET @demo_booking_4 = (SELECT b.booking_id FROM booking b
    JOIN customer c ON c.customer_id=b.customer_id
    WHERE c.phone_no='DEMO-CUST-2026-004'
      AND b.specific_instructions='DEMO SAMPLE: Anniversary at Peacock Banquet Hall'
    ORDER BY b.booking_id LIMIT 1);
INSERT INTO booking (customer_id,venue_id,booking_date,specific_instructions)
SELECT c.customer_id,v.venue_id,'2027-03-06',
       'DEMO SAMPLE: Anniversary at Peacock Banquet Hall'
FROM customer c JOIN venue v ON v.name='Peacock Banquet Hall'
WHERE c.phone_no='DEMO-CUST-2026-004' AND @demo_booking_4 IS NULL;
SET @demo_booking_4 = (SELECT b.booking_id FROM booking b
    JOIN customer c ON c.customer_id=b.customer_id
    WHERE c.phone_no='DEMO-CUST-2026-004'
      AND b.specific_instructions='DEMO SAMPLE: Anniversary at Peacock Banquet Hall'
    ORDER BY b.booking_id LIMIT 1);

INSERT IGNORE INTO booking_slot (booking_id,venue_id,slot_date,slot_id)
SELECT b.booking_id,b.venue_id,b.booking_date,slots.slot_id
FROM booking b
JOIN (
    SELECT @demo_booking_1 AS booking_id,1 AS slot_id UNION ALL
    SELECT @demo_booking_1,2 UNION ALL
    SELECT @demo_booking_2,3 UNION ALL
    SELECT @demo_booking_3,4 UNION ALL
    SELECT @demo_booking_4,3
) slots ON slots.booking_id=b.booking_id
WHERE b.booking_status='ACTIVE';

INSERT IGNORE INTO booking_services (booking_id,tier_id,quantity_booked)
SELECT sample.booking_id,st.tier_id,sample.quantity
FROM (
    SELECT @demo_booking_1 AS booking_id,'Catering' AS service_name,'Vegetarian Plate' AS tier_name,120 AS quantity UNION ALL
    SELECT @demo_booking_1,'Catering','Non-Vegetarian Plate',45 UNION ALL
    SELECT @demo_booking_1,'Floral Decoration','Floral Stage Package',1 UNION ALL
    SELECT @demo_booking_1,'Sound and Lighting','Event Sound and Lighting',1 UNION ALL
    SELECT @demo_booking_2,'Catering','Vegetarian Plate',100 UNION ALL
    SELECT @demo_booking_2,'Catering','Non-Vegetarian Plate',50 UNION ALL
    SELECT @demo_booking_2,'Catering','Children Plate',15 UNION ALL
    SELECT @demo_booking_2,'Floral Decoration','Table Centrepiece',12 UNION ALL
    SELECT @demo_booking_2,'Photography','Event Photography Package',1 UNION ALL
    SELECT @demo_booking_3,'Catering','Vegetarian Plate',140 UNION ALL
    SELECT @demo_booking_3,'Catering','Non-Vegetarian Plate',60 UNION ALL
    SELECT @demo_booking_3,'Catering','Children Plate',20 UNION ALL
    SELECT @demo_booking_3,'Floral Decoration','Floral Stage Package',1 UNION ALL
    SELECT @demo_booking_3,'Sound and Lighting','Event Sound and Lighting',1 UNION ALL
    SELECT @demo_booking_3,'Sound and Lighting','Wireless Microphone',2 UNION ALL
    SELECT @demo_booking_3,'Photography','Event Photography Package',1 UNION ALL
    SELECT @demo_booking_4,'Catering','Vegetarian Plate',80 UNION ALL
    SELECT @demo_booking_4,'Catering','Non-Vegetarian Plate',25 UNION ALL
    SELECT @demo_booking_4,'Floral Decoration','Table Centrepiece',10 UNION ALL
    SELECT @demo_booking_4,'Photography','Event Photography Package',1
) sample
JOIN service s ON s.service_name=sample.service_name
JOIN service_tier st ON st.service_id=s.service_id AND st.tier_name=sample.tier_name
JOIN booking b ON b.booking_id=sample.booking_id AND b.booking_status='ACTIVE'
WHERE sample.booking_id IS NOT NULL;

-- Seed payment states once; later operator-entered payments are left alone.
UPDATE booking b JOIN vw_booking_cost bill ON bill.booking_id=b.booking_id
SET b.paid_till=ROUND(bill.cost * 0.40,2)
WHERE b.booking_id=@demo_booking_1 AND b.paid_till=0 AND b.booking_status='ACTIVE';
UPDATE booking b JOIN vw_booking_cost bill ON bill.booking_id=b.booking_id
SET b.paid_till=bill.cost
WHERE b.booking_id=@demo_booking_2 AND b.paid_till=0 AND b.booking_status='ACTIVE';
UPDATE booking b JOIN vw_booking_cost bill ON bill.booking_id=b.booking_id
SET b.paid_till=ROUND(bill.cost * 0.25,2)
WHERE b.booking_id=@demo_booking_4 AND b.paid_till=0 AND b.booking_status='ACTIVE';

-- One November payroll month lets the CLI demonstrate deductions and net pay.
-- INSERT IGNORE preserves any payroll row already entered for these employees.
INSERT IGNORE INTO pay_roll
    (employee_id,pay_month,pay_date,fiscal_year,salary,pf_deduction,tds)
SELECT e.employee_id,'2026-11-01','2026-11-30',fy.year,e.salary,
       ROUND(e.salary * pr.rate / 100,2),
       (SELECT ROUND(SUM(
            GREATEST(LEAST(e.salary * 12,COALESCE(slab.slab_upper_limit,e.salary * 12))
                     - slab.slab_lower_limit,0) * slab.slab_rate / 100
        ) / 12,2)
        FROM it_slab slab WHERE slab.fiscal_year=fy.year)
FROM employee e
JOIN fiscal_year fy ON fy.year=2026
JOIN pf_rate pr ON pr.fiscal_year=fy.year
WHERE e.name IN ('Demo Chef','Demo Decorator','Demo Sound Operator');
