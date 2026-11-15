"""Menu-driven receptionist/admin interface for the backend."""

from decimal import Decimal, InvalidOperation

from mysql.connector import Error

from .backend import EventManagementBackend
from .db import read_connection


APP = EventManagementBackend()


def ask(label, *, required=True):
    while True:
        value = input(label).strip()
        if value or not required:
            return value
        print("Please enter a value.")


def ask_int(label, *, required=True):
    while True:
        raw = ask(label, required=required)
        if not raw and not required:
            return None
        try:
            return int(raw)
        except ValueError:
            print("Enter a whole number.")


def ask_decimal(label):
    while True:
        try:
            value = Decimal(ask(label))
            if value.is_finite() and value >= 0:
                return value
        except InvalidOperation:
            pass
        print("Enter a non-negative amount, for example 1250.00.")


def ask_yes_no(label, default=False):
    suffix = " [Y/n] " if default else " [y/N] "
    while True:
        answer = input(label + suffix).strip().lower()
        if not answer:
            return default
        if answer in ("y", "yes"):
            return True
        if answer in ("n", "no"):
            return False
        print("Enter y or n.")


def show(rows, columns):
    if not rows:
        print("No records found.")
        return
    headers = [title for title, _ in columns]
    values = [[str(row.get(key, "")) for _, key in columns] for row in rows]
    widths = [max(len(headers[i]), *(len(row[i]) for row in values)) for i in range(len(headers))]
    print(" | ".join(headers[i].ljust(widths[i]) for i in range(len(headers))))
    print("-+-".join("-" * width for width in widths))
    for row in values:
        print(" | ".join(row[i].ljust(widths[i]) for i in range(len(headers))))


def handle(action):
    try:
        action()
    except ValueError as exc:
        print(f"Could not complete that action: {exc}")
    except Error as exc:
        if exc.errno == 1062:
            print("That name or time slot is already in use.")
        elif exc.errno == 1452:
            print("The selected record does not exist. Check the ID and try again.")
        elif exc.errno == 1451:
            print("This record is still used by bookings, employees, or payroll history and cannot be removed.")
        elif exc.errno == 3819:
            print("One of the values is outside the allowed range.")
        else:
            print(f"Database could not complete that action: {exc.msg}")


def show_venues():
    show(APP.list_venues(), [
        ("ID", "venue_id"), ("Venue", "name"), ("Type", "type"),
        ("Area sq ft", "area"), ("Capacity", "capacity"), ("Rate/slot", "rate"),
    ])


def show_services():
    services = APP.list_services()
    show(services, [("ID", "service_id"), ("Service", "service_name"), ("Contracted", "is_contracted")])
    print("\nService tiers:")
    show(APP.list_service_tiers(), [
        ("Tier ID", "tier_id"), ("Service", "service_name"), ("Tier", "tier_name"),
        ("Unit cost", "unit_cost"), ("Description", "description"),
    ])


def choose_service():
    show(APP.list_services(), [("ID", "service_id"), ("Service", "service_name")])
    return ask_int("Service ID: ")


def booking_detail_action():
    details = APP.booking_details(ask_int("Booking ID: "))
    fields = [
        ("Booking", "booking_id"), ("Date", "booking_date"), ("Status", "booking_status"),
        ("Customer", "customer_name"), ("Phone", "customer_phone"),
        ("Venue", "venue_name"), ("Slots", "slots"), ("Total", "cost"),
        ("Paid", "paid_till"), ("Dues", "dues"), ("Payment", "payment_status"),
    ]
    show([details], fields)
    print("\nBooked slots:")
    show(details["slots_booked"], [("ID", "slot_id"), ("Slot", "slot_name"),
                                    ("Start", "slot_start_time"), ("End", "slot_end_time")])
    print("\nBooked services:")
    show(details["services"], [("Service", "service_name"), ("Tier", "tier_name"),
                               ("Qty", "quantity_booked"), ("Actual", "actual_quantity"),
                               ("Unit", "unit_cost"), ("Total", "total_tier_cost")])
    if details.get("specific_instructions"):
        print("Instructions:", details["specific_instructions"])


def create_booking_action():
    show_venues()
    venue_id = ask_int("Venue ID: ")
    name = ask("Customer name: ")
    phone = ask("Customer phone: ")
    event_date = ask("Event date (YYYY-MM-DD): ")
    print("\nAvailable slot types:")
    show(APP.list_event_slots(), [("ID", "slot_id"), ("Slot", "slot_name"),
                                  ("Start", "slot_start_time"), ("End", "slot_end_time")])
    slot_ids = [int(part.strip()) for part in ask("Slot IDs separated by commas: ").split(",")]
    print("\nAvailable service tiers (leave the ID blank when finished):")
    show(APP.list_service_tiers(), [("ID", "tier_id"), ("Service", "service_name"),
                                    ("Tier", "tier_name"), ("Unit cost", "unit_cost")])
    service_lines = []
    while True:
        tier_id = ask_int("Tier ID (blank to finish): ", required=False)
        if tier_id is None:
            break
        quantity = ask_int("Quantity: ")
        service_lines.append({"tier_id": tier_id, "quantity": quantity})
    instructions = ask("Event instructions (optional): ", required=False)
    booking_id, cost = APP.create_booking(
        customer_name=name,
        customer_phone=phone,
        venue_id=venue_id,
        booking_date=event_date,
        slot_ids=slot_ids,
        services=service_lines,
        specific_instructions=instructions,
    )
    print(f"Booking {booking_id} created. Current total: ₹{cost}.")


def bookings_menu():
    while True:
        print("\nBookings\n1. List bookings\n2. Booking details\n3. Create booking\n"
              "4. Record payment\n5. Cancel booking\n6. Enter actual service quantities\n0. Back")
        choice = ask("Choose: ", required=False)
        if choice == "0":
            return
        if choice == "1":
            handle(lambda: show(APP.list_bookings(), [
                ("ID", "booking_id"), ("Date", "booking_date"), ("Status", "booking_status"),
                ("Customer", "customer_name"), ("Venue", "venue_name"), ("Slots", "slots"),
                ("Total", "cost"), ("Paid", "paid_till"), ("Dues", "dues"),
            ]))
        elif choice == "2":
            handle(booking_detail_action)
        elif choice == "3":
            handle(create_booking_action)
        elif choice == "4":
            def payment():
                booking_id = ask_int("Booking ID: ")
                amount = ask_decimal("Payment amount: ")
                APP.record_payment(booking_id, amount)
                print("Payment recorded; the booking balance was updated.")
            handle(payment)
        elif choice == "5":
            def cancel():
                APP.cancel_booking(ask_int("Booking ID to cancel: "))
                print("Booking cancelled and its venue slots released.")
            handle(cancel)
        elif choice == "6":
            def actual_quantity():
                booking_id = ask_int("Booking ID: ")
                tier_id = ask_int("Service tier ID: ")
                quantity = ask_int("Actual quantity used: ")
                APP.update_actual_service_quantity(booking_id, tier_id, quantity)
                print("Actual quantity saved.")
            handle(actual_quantity)
        else:
            print("Choose one of the listed options.")


def payroll_estimate_action():
    year = ask_int("Tax year (for example 2026): ")
    show(APP.payroll_estimates(year), [
        ("Employee ID", "employee_id"), ("Employee", "employee_name"), ("Service", "service_name"),
        ("Monthly", "monthly_salary"), ("Annual", "annual_salary"),
        ("PF estimate", "estimated_monthly_pf"), ("TDS estimate", "estimated_monthly_tds"),
    ])


def process_payroll_action():
    month = ask("Pay month, first day (YYYY-MM-01): ")
    employee_id = ask_int("Employee ID (blank to process all): ", required=False)
    count = APP.process_payroll(month, employee_id)
    print(f"Payroll created for {count} employee(s).")
    show(APP.payroll_for_month(month), [
        ("Employee", "employee_name"), ("Month", "pay_month"), ("Salary", "salary"),
        ("PF", "pf_deduction"), ("TDS", "tds"), ("Net", "net_salary"),
    ])


def employees_menu():
    while True:
        print("\nEmployees and payroll\n1. List employees\n2. Add employee\n3. Update employee\n"
              "4. Remove employee\n5. Preview PF/TDS\n6. Process monthly payroll\n"
              "7. View payroll month\n0. Back")
        choice = ask("Choose: ", required=False)
        if choice == "0":
            return
        if choice == "1":
            handle(lambda: show(APP.list_employees(), [
                ("ID", "employee_id"), ("Name", "name"), ("Service", "service_name"),
                ("Role", "role"), ("Salary", "salary"), ("Phone", "phone_no"),
            ]))
        elif choice in ("2", "3"):
            def save_employee():
                employee_id = ask_int("Employee ID: ") if choice == "3" else None
                service_id = choose_service()
                name = ask("Name: ")
                role = ask("Role: ")
                salary = ask_decimal("Monthly salary: ")
                phone = ask("Phone (optional): ", required=False)
                if employee_id is None:
                    created = APP.add_employee(service_id, name, role, salary, phone)
                    print(f"Employee {created} added.")
                else:
                    APP.update_employee(employee_id, service_id, name, role, salary, phone)
                    print("Employee updated.")
            handle(save_employee)
        elif choice == "4":
            def remove_employee():
                APP.delete_employee(ask_int("Employee ID to remove: "))
                print("Employee removed.")
            handle(remove_employee)
        elif choice == "5":
            handle(payroll_estimate_action)
        elif choice == "6":
            handle(process_payroll_action)
        elif choice == "7":
            def view_payroll():
                month = ask("Pay month (YYYY-MM-DD): ")
                show(APP.payroll_for_month(month), [
                    ("ID", "employee_id"), ("Employee", "employee_name"), ("Role", "role"),
                    ("Salary", "salary"), ("PF", "pf_deduction"), ("TDS", "tds"),
                    ("Net", "net_salary"), ("View TDS", "calculated_monthly_tds"),
                ])
            handle(view_payroll)
        else:
            print("Choose one of the listed options.")


def catalog_menu():
    while True:
        print("\nVenues and service catalogue\n1. List venues\n2. Add venue\n3. Update venue\n"
              "4. Remove venue\n5. List services and tiers\n6. Add service\n7. Update service\n"
              "8. Remove service\n9. Add service tier\n10. Update service tier\n"
              "11. Remove service tier\n0. Back")
        choice = ask("Choose: ", required=False)
        if choice == "0":
            return
        if choice == "1":
            handle(show_venues)
        elif choice in ("2", "3"):
            def save_venue():
                venue_id = ask_int("Venue ID: ") if choice == "3" else None
                name = ask("Venue name: ")
                kind = ask("Venue type: ", required=False)
                area = ask_decimal("Area in square feet: ")
                capacity = ask_int("Guest capacity: ")
                rate = ask_decimal("Rate per event slot: ")
                description = ask("Description (optional): ", required=False)
                if venue_id is None:
                    created = APP.add_venue(name, kind, area, capacity, rate, description)
                    print(f"Venue {created} added.")
                else:
                    APP.update_venue(venue_id, name, kind, area, capacity, rate, description)
                    print("Venue updated.")
            handle(save_venue)
        elif choice == "4":
            def remove_venue():
                APP.delete_venue(ask_int("Venue ID to remove: "))
                print("Venue removed.")
            handle(remove_venue)
        elif choice == "5":
            handle(show_services)
        elif choice == "6":
            def add_service():
                name = ask("Service name: ")
                contracted = ask_yes_no("Is this service contracted?")
                print(f"Service {APP.add_service(name, contracted)} added.")
            handle(add_service)
        elif choice == "7":
            def update_service():
                service_id = choose_service()
                name = ask("New service name: ")
                contracted = ask_yes_no("Is this service contracted?")
                APP.update_service(service_id, name, contracted)
                print("Service updated.")
            handle(update_service)
        elif choice == "8":
            def remove_service():
                service_id = choose_service()
                APP.delete_service(service_id)
                print("Service removed.")
            handle(remove_service)
        elif choice == "9":
            def add_tier():
                service_id = choose_service()
                name = ask("Tier/package name: ")
                description = ask("Description (optional): ", required=False)
                cost = ask_decimal("Unit cost: ")
                print(f"Service tier {APP.add_service_tier(service_id, name, description, cost)} added.")
            handle(add_tier)
        elif choice in ("10", "11"):
            def tier_action():
                show(APP.list_service_tiers(), [("Tier ID", "tier_id"),
                    ("Service", "service_name"), ("Tier", "tier_name"), ("Unit", "unit_cost")])
                tier_id = ask_int("Tier ID: ")
                if choice == "11":
                    APP.delete_service_tier(tier_id)
                    print("Service tier removed.")
                    return
                service_id = choose_service()
                name = ask("New tier name: ")
                description = ask("Description (optional): ", required=False)
                cost = ask_decimal("Unit cost: ")
                APP.update_service_tier(tier_id, service_id, name, description, cost)
                print("Service tier updated.")
            handle(tier_action)
        else:
            print("Choose one of the listed options.")


def reports_menu():
    print("\nReports\n1. Monthly active-booking revenue\n0. Back")
    choice = ask("Choose: ", required=False)
    if choice == "1":
        year = ask_int("Calendar year (blank for all): ", required=False)
        handle(lambda: show(APP.monthly_revenue(year), [
            ("Year", "year"), ("Month", "month"), ("Bookings", "booking_count"), ("Revenue", "revenue"),
        ]))


def main():
    try:
        with read_connection() as connection:
            connection.ping(reconnect=False, attempts=1, delay=0)
    except Error as exc:
        print(f"Could not connect to the event_management database: {exc.msg}")
        print("Run `python setup_db.py` first and check the connection values in .env.")
        return

    while True:
        print("\nEvent Management Desk\n1. Bookings\n2. Employees and payroll\n"
              "3. Venues and services\n4. Reports\n0. Exit")
        choice = ask("Choose: ", required=False)
        if choice == "0":
            print("Goodbye.")
            return
        if choice == "1":
            bookings_menu()
        elif choice == "2":
            employees_menu()
        elif choice == "3":
            catalog_menu()
        elif choice == "4":
            reports_menu()
        else:
            print("Choose one of the listed options.")


if __name__ == "__main__":
    main()
