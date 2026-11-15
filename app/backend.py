"""Database operations for the event-management operator CLI."""

from datetime import date
from decimal import Decimal

from .db import read_connection, transaction


class EventManagementBackend:
    """Application backend; SQL owns costs, constraints, and payroll arithmetic."""

    @staticmethod
    def _fetch_all(sql: str, params=()):
        with read_connection() as connection:
            cursor = connection.cursor(dictionary=True)
            cursor.execute(sql, params)
            return cursor.fetchall()

    @staticmethod
    def _fetch_one(sql: str, params=()):
        with read_connection() as connection:
            cursor = connection.cursor(dictionary=True)
            cursor.execute(sql, params)
            return cursor.fetchone()

    def list_venues(self):
        return self._fetch_all(
            "SELECT venue_id, name, type, area, capacity, rate, description "
            "FROM venue ORDER BY name"
        )

    def add_venue(self, name, venue_type, area, capacity, rate, description):
        with transaction() as connection:
            cursor = connection.cursor()
            cursor.execute(
                "INSERT INTO venue(name,type,area,capacity,rate,description) "
                "VALUES(%s,%s,%s,%s,%s,%s)",
                (name, venue_type or None, area, capacity, rate, description or None),
            )
            return cursor.lastrowid

    def update_venue(self, venue_id, name, venue_type, area, capacity, rate, description):
        with transaction() as connection:
            cursor = connection.cursor()
            cursor.execute("SELECT venue_id FROM venue WHERE venue_id=%s FOR UPDATE", (venue_id,))
            if cursor.fetchone() is None:
                raise ValueError("No venue has that ID.")
            cursor.execute(
                "UPDATE venue SET name=%s,type=%s,area=%s,capacity=%s,rate=%s,description=%s "
                "WHERE venue_id=%s",
                (name, venue_type or None, area, capacity, rate, description or None, venue_id),
            )

    def delete_venue(self, venue_id):
        with transaction() as connection:
            cursor = connection.cursor()
            cursor.execute("DELETE FROM venue WHERE venue_id=%s", (venue_id,))
            if cursor.rowcount == 0:
                raise ValueError("No venue has that ID.")

    def list_event_slots(self):
        return self._fetch_all("SELECT * FROM event_slot ORDER BY slot_id")

    def list_customers(self, search=""):
        term = f"%{search}%"
        return self._fetch_all(
            "SELECT customer_id,name,phone_no FROM customer "
            "WHERE name LIKE %s OR phone_no LIKE %s ORDER BY name LIMIT 30",
            (term, term),
        )

    def list_bookings(self, booking_date=None, status=None):
        sql = (
            "SELECT booking_id,booking_date,booking_status,customer_name,customer_phone,"
            "venue_name,slots,cost,paid_till,dues,payment_status "
            "FROM vw_booking_details WHERE 1=1"
        )
        params = []
        if booking_date:
            sql += " AND booking_date=%s"
            params.append(booking_date)
        if status:
            if status not in ("ACTIVE", "CANCELLED"):
                raise ValueError("Status must be ACTIVE or CANCELLED.")
            sql += " AND booking_status=%s"
            params.append(status)
        sql += " ORDER BY booking_date DESC, booking_id DESC LIMIT 100"
        return self._fetch_all(sql, tuple(params))

    def booking_details(self, booking_id):
        details = self._fetch_one(
            "SELECT * FROM vw_booking_details WHERE booking_id=%s", (booking_id,)
        )
        if details is None:
            raise ValueError("No booking has that ID.")
        details["slots_booked"] = self._fetch_all(
            "SELECT es.slot_id,es.slot_name,es.slot_start_time,es.slot_end_time "
            "FROM booking_slot bs JOIN event_slot es ON es.slot_id=bs.slot_id "
            "WHERE bs.booking_id=%s ORDER BY es.slot_id",
            (booking_id,),
        )
        details["services"] = self._fetch_all(
            "SELECT service_name,tier_name,quantity_booked,actual_quantity,unit_cost,"
            "total_tier_cost,specific_instructions "
            "FROM vw_booking_services WHERE booking_id=%s ORDER BY service_name,tier_name",
            (booking_id,),
        )
        return details

    def create_booking(
        self,
        *,
        customer_name,
        customer_phone,
        venue_id,
        booking_date,
        slot_ids,
        services=(),
        specific_instructions="",
    ):
        slots = [int(slot_id) for slot_id in slot_ids]
        if not slots:
            raise ValueError("Choose at least one event slot.")
        if len(slots) != len(set(slots)):
            raise ValueError("A slot can only be selected once for a booking.")
        with transaction() as connection:
            cursor = connection.cursor(dictionary=True)
            cursor.execute("SELECT venue_id FROM venue WHERE venue_id=%s FOR UPDATE", (venue_id,))
            if cursor.fetchone() is None:
                raise ValueError("No venue has that ID.")

            cursor.execute(
                "SELECT customer_id FROM customer WHERE phone_no=%s "
                "ORDER BY customer_id DESC LIMIT 1 FOR UPDATE",
                (customer_phone,),
            )
            customer = cursor.fetchone()
            if customer is None:
                cursor.execute(
                    "INSERT INTO customer(name,phone_no) VALUES(%s,%s)",
                    (customer_name, customer_phone),
                )
                customer_id = cursor.lastrowid
            else:
                customer_id = customer["customer_id"]

            cursor.execute(
                "INSERT INTO booking(customer_id,venue_id,booking_date,specific_instructions) "
                "VALUES(%s,%s,%s,%s)",
                (customer_id, venue_id, booking_date, specific_instructions or None),
            )
            booking_id = cursor.lastrowid
            cursor.executemany(
                "INSERT INTO booking_slot(booking_id,venue_id,slot_date,slot_id) "
                "VALUES(%s,%s,%s,%s)",
                [(booking_id, venue_id, booking_date, slot_id) for slot_id in slots],
            )

            seen_tiers = set()
            for line in services:
                tier_id = int(line["tier_id"])
                quantity = int(line["quantity"])
                if tier_id in seen_tiers:
                    raise ValueError("Each service tier can only be entered once per booking.")
                if quantity <= 0:
                    raise ValueError("Service quantities must be greater than zero.")
                seen_tiers.add(tier_id)
                cursor.execute(
                    "INSERT INTO booking_services(booking_id,tier_id,quantity_booked,"
                    "specific_instructions) VALUES(%s,%s,%s,%s)",
                    (booking_id, tier_id, quantity, line.get("instructions") or None),
                )

            cursor.execute("SELECT cost FROM vw_booking_cost WHERE booking_id=%s", (booking_id,))
            cost = cursor.fetchone()["cost"]
            return booking_id, cost

    def record_payment(self, booking_id, amount: Decimal):
        if amount <= 0:
            raise ValueError("Payment amount must be greater than zero.")
        with transaction() as connection:
            cursor = connection.cursor(dictionary=True)
            cursor.execute(
                "SELECT booking_status,paid_till FROM booking WHERE booking_id=%s FOR UPDATE",
                (booking_id,),
            )
            booking = cursor.fetchone()
            if booking is None:
                raise ValueError("No booking has that ID.")
            if booking["booking_status"] != "ACTIVE":
                raise ValueError("Payments can only be recorded for active bookings.")
            cursor.execute("SELECT cost FROM vw_booking_cost WHERE booking_id=%s", (booking_id,))
            cost = cursor.fetchone()["cost"]
            if booking["paid_till"] + amount > cost:
                raise ValueError(f"Payment is above the outstanding balance of {cost - booking['paid_till']}.")
            cursor.execute(
                "UPDATE booking SET paid_till=paid_till+%s WHERE booking_id=%s",
                (amount, booking_id),
            )

    def cancel_booking(self, booking_id):
        with transaction() as connection:
            cursor = connection.cursor(dictionary=True)
            cursor.execute(
                "SELECT booking_status FROM booking WHERE booking_id=%s FOR UPDATE",
                (booking_id,),
            )
            booking = cursor.fetchone()
            if booking is None:
                raise ValueError("No booking has that ID.")
            if booking["booking_status"] == "CANCELLED":
                raise ValueError("That booking is already cancelled.")
            cursor.execute("DELETE FROM booking_slot WHERE booking_id=%s", (booking_id,))
            cursor.execute(
                "UPDATE booking SET booking_status='CANCELLED' WHERE booking_id=%s",
                (booking_id,),
            )

    def update_actual_service_quantity(self, booking_id, tier_id, actual_quantity):
        if actual_quantity < 0:
            raise ValueError("Actual quantity cannot be negative.")
        with transaction() as connection:
            cursor = connection.cursor()
            cursor.execute(
                "SELECT booking_id FROM booking_services WHERE booking_id=%s AND tier_id=%s FOR UPDATE",
                (booking_id, tier_id),
            )
            if cursor.fetchone() is None:
                raise ValueError("That service tier is not on this booking.")
            cursor.execute(
                "UPDATE booking_services SET actual_quantity=%s "
                "WHERE booking_id=%s AND tier_id=%s",
                (actual_quantity, booking_id, tier_id),
            )

    def list_services(self):
        return self._fetch_all("SELECT * FROM service ORDER BY service_name")

    def list_service_tiers(self, service_id=None):
        sql = (
            "SELECT st.tier_id,st.service_id,s.service_name,st.tier_name,st.description,st.unit_cost "
            "FROM service_tier st JOIN service s ON s.service_id=st.service_id"
        )
        params = ()
        if service_id is not None:
            sql += " WHERE st.service_id=%s"
            params = (service_id,)
        return self._fetch_all(sql + " ORDER BY s.service_name,st.tier_name", params)

    def add_service(self, service_name, is_contracted=False):
        with transaction() as connection:
            cursor = connection.cursor()
            cursor.execute(
                "INSERT INTO service(service_name,is_contracted) VALUES(%s,%s)",
                (service_name, is_contracted),
            )
            return cursor.lastrowid

    def update_service(self, service_id, service_name, is_contracted):
        with transaction() as connection:
            cursor = connection.cursor()
            cursor.execute("SELECT service_id FROM service WHERE service_id=%s FOR UPDATE", (service_id,))
            if cursor.fetchone() is None:
                raise ValueError("No service has that ID.")
            cursor.execute(
                "UPDATE service SET service_name=%s,is_contracted=%s WHERE service_id=%s",
                (service_name, is_contracted, service_id),
            )

    def delete_service(self, service_id):
        with transaction() as connection:
            cursor = connection.cursor()
            cursor.execute("DELETE FROM service WHERE service_id=%s", (service_id,))
            if cursor.rowcount == 0:
                raise ValueError("No service has that ID.")

    def add_service_tier(self, service_id, tier_name, description, unit_cost):
        with transaction() as connection:
            cursor = connection.cursor()
            cursor.execute(
                "INSERT INTO service_tier(service_id,tier_name,description,unit_cost) "
                "VALUES(%s,%s,%s,%s)",
                (service_id, tier_name, description or None, unit_cost),
            )
            return cursor.lastrowid

    def update_service_tier(self, tier_id, service_id, tier_name, description, unit_cost):
        with transaction() as connection:
            cursor = connection.cursor()
            cursor.execute("SELECT tier_id FROM service_tier WHERE tier_id=%s FOR UPDATE", (tier_id,))
            if cursor.fetchone() is None:
                raise ValueError("No service tier has that ID.")
            cursor.execute(
                "UPDATE service_tier SET service_id=%s,tier_name=%s,description=%s,unit_cost=%s "
                "WHERE tier_id=%s",
                (service_id, tier_name, description or None, unit_cost, tier_id),
            )

    def delete_service_tier(self, tier_id):
        with transaction() as connection:
            cursor = connection.cursor()
            cursor.execute("DELETE FROM service_tier WHERE tier_id=%s", (tier_id,))
            if cursor.rowcount == 0:
                raise ValueError("No service tier has that ID.")

    def list_employees(self, service_id=None):
        sql = (
            "SELECT e.employee_id,e.service_id,s.service_name,e.name,e.role,e.salary,e.phone_no "
            "FROM employee e JOIN service s ON s.service_id=e.service_id"
        )
        params = ()
        if service_id is not None:
            sql += " WHERE e.service_id=%s"
            params = (service_id,)
        return self._fetch_all(sql + " ORDER BY e.name", params)

    def add_employee(self, service_id, name, role, salary, phone_no):
        with transaction() as connection:
            cursor = connection.cursor()
            cursor.execute(
                "INSERT INTO employee(service_id,name,role,salary,phone_no) VALUES(%s,%s,%s,%s,%s)",
                (service_id, name, role, salary, phone_no or None),
            )
            return cursor.lastrowid

    def update_employee(self, employee_id, service_id, name, role, salary, phone_no):
        with transaction() as connection:
            cursor = connection.cursor()
            cursor.execute("SELECT employee_id FROM employee WHERE employee_id=%s FOR UPDATE", (employee_id,))
            if cursor.fetchone() is None:
                raise ValueError("No employee has that ID.")
            cursor.execute(
                "UPDATE employee SET service_id=%s,name=%s,role=%s,salary=%s,phone_no=%s "
                "WHERE employee_id=%s",
                (service_id, name, role, salary, phone_no or None, employee_id),
            )

    def delete_employee(self, employee_id):
        with transaction() as connection:
            cursor = connection.cursor()
            cursor.execute("DELETE FROM employee WHERE employee_id=%s", (employee_id,))
            if cursor.rowcount == 0:
                raise ValueError("No employee has that ID.")

    def payroll_estimates(self, fiscal_year):
        return self._fetch_all(
            "SELECT t.employee_id,t.employee_name,t.role,s.service_name,t.fiscal_year,"
            "t.monthly_salary,t.annual_salary,t.estimated_monthly_pf,t.estimated_monthly_tds "
            "FROM vw_employee_tax_estimate t JOIN service s ON s.service_id=t.service_id "
            "WHERE t.fiscal_year=%s ORDER BY t.employee_name",
            (fiscal_year,),
        )

    def process_payroll(self, pay_month, employee_id=None):
        month = date.fromisoformat(str(pay_month)).replace(day=1)
        month_value = month.isoformat()
        sql = """INSERT INTO pay_roll
                 (employee_id,pay_month,pay_date,fiscal_year,salary,pf_deduction,tds)
                 SELECT e.employee_id,%s,LAST_DAY(%s),fy.year,e.salary,
                        ROUND(e.salary * pr.rate / 100,2),
                        (SELECT ROUND(SUM(
                            GREATEST(LEAST(e.salary * 12,
                                           COALESCE(s.slab_upper_limit,e.salary * 12))
                                     - s.slab_lower_limit,0) * s.slab_rate / 100
                        ) / 12,2)
                         FROM it_slab s WHERE s.fiscal_year=fy.year)
                 FROM employee e
                 JOIN fiscal_year fy
                   ON fy.year=YEAR(%s)-(MONTH(%s) < 4)
                 JOIN pf_rate pr ON pr.fiscal_year=fy.year
                 WHERE (%s IS NULL OR e.employee_id=%s)"""
        params = (month_value, month_value, month_value, month_value, employee_id, employee_id)
        with transaction() as connection:
            cursor = connection.cursor()
            cursor.execute(sql, params)
            count = cursor.rowcount
            if count == 0:
                raise ValueError("No payroll rows were created; check the employee and fiscal-year rates.")
            return count

    def payroll_for_month(self, pay_month):
        month = date.fromisoformat(str(pay_month)).replace(day=1).isoformat()
        return self._fetch_all(
            "SELECT employee_id,employee_name,role,pay_month,pay_date,salary,pf_deduction,tds,"
            "calculated_monthly_tds,net_salary FROM vw_payroll_summary "
            "WHERE pay_month=%s ORDER BY employee_name",
            (month,),
        )

    def monthly_revenue(self, year=None):
        if year is None:
            return self._fetch_all("SELECT * FROM vw_monthly_revenue ORDER BY year DESC,month DESC")
        return self._fetch_all(
            "SELECT * FROM vw_monthly_revenue WHERE year=%s ORDER BY month", (year,)
        )

