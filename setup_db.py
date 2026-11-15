"""Create or upgrade the schema and insert re-runnable starter data."""

from pathlib import Path

import mysql.connector
import sqlparse

from app.config import PROJECT_ROOT, settings
from app.db import connect


DDL = PROJECT_ROOT / "SQL Files" / "ddl.sql"
SEED = PROJECT_ROOT / "SQL Files" / "sample_data.sql"

# Local and referenced columns, in order. These checks also upgrade databases
# created by the old DDL, where inline REFERENCES did not create real FKs.
FOREIGN_KEYS = (
    ("booking", "fk_booking_customer", ("customer_id",), "customer", ("customer_id",)),
    ("booking", "fk_booking_venue", ("venue_id",), "venue", ("venue_id",)),
    ("booking_slot", "fk_booking_slot_booking", ("booking_id", "venue_id", "slot_date"),
     "booking", ("booking_id", "venue_id", "booking_date")),
    ("booking_slot", "fk_booking_slot_event_slot", ("slot_id",), "event_slot", ("slot_id",)),
    ("service_tier", "fk_service_tier_service", ("service_id",), "service", ("service_id",)),
    ("booking_services", "fk_booking_services_booking", ("booking_id",), "booking", ("booking_id",)),
    ("booking_services", "fk_booking_services_tier", ("tier_id",), "service_tier", ("tier_id",)),
    ("employee", "fk_employee_service", ("service_id",), "service", ("service_id",)),
    ("it_slab", "fk_it_slab_fiscal_year", ("fiscal_year",), "fiscal_year", ("year",)),
    ("pf_rate", "fk_pf_rate_fiscal_year", ("fiscal_year",), "fiscal_year", ("year",)),
    ("pay_roll", "fk_pay_roll_employee", ("employee_id",), "employee", ("employee_id",)),
    ("pay_roll", "fk_pay_roll_fiscal_year", ("fiscal_year",), "fiscal_year", ("year",)),
)


def run_file(cursor, path: Path) -> None:
    for statement in sqlparse.split(path.read_text(encoding="utf-8")):
        if statement.strip():
            cursor.execute(statement)


def ensure_foreign_keys(cursor) -> int:
    added = 0
    schema_name = settings.database
    for table, name, columns, ref_table, ref_columns in FOREIGN_KEYS:
        cursor.execute(
            """SELECT GROUP_CONCAT(COLUMN_NAME ORDER BY ORDINAL_POSITION),
                      GROUP_CONCAT(REFERENCED_COLUMN_NAME ORDER BY ORDINAL_POSITION),
                      REFERENCED_TABLE_NAME
               FROM information_schema.KEY_COLUMN_USAGE
               WHERE CONSTRAINT_SCHEMA = %s AND TABLE_NAME = %s
                 AND REFERENCED_TABLE_NAME IS NOT NULL
               GROUP BY CONSTRAINT_NAME, REFERENCED_TABLE_NAME""",
            (schema_name, table),
        )
        expected_local = ",".join(columns)
        expected_remote = ",".join(ref_columns)
        relations = cursor.fetchall()
        if any(local == expected_local and remote == expected_remote and target == ref_table
               for local, remote, target in relations):
            continue
        local_sql = ", ".join(f"`{column}`" for column in columns)
        remote_sql = ", ".join(f"`{column}`" for column in ref_columns)
        cursor.execute(
            f"ALTER TABLE `{table}` ADD CONSTRAINT `{name}` "
            f"FOREIGN KEY ({local_sql}) REFERENCES `{ref_table}` ({remote_sql})"
        )
        added += 1
    return added


def main() -> None:
    if settings.database != "event_management":
        raise SystemExit(
            "DB_NAME must be event_management because the supplied SQL files use that schema name."
        )
    connection = connect(select_database=False)
    try:
        cursor = connection.cursor()
        run_file(cursor, DDL)
        added = ensure_foreign_keys(cursor)
        run_file(cursor, SEED)
        connection.commit()
        print("Schema is ready. Demo customers, bookings, staff, service lines, and payroll data are loaded.")
        print(f"Foreign keys added during this run: {added}.")
    except mysql.connector.Error as exc:
        connection.rollback()
        print(f"Database setup stopped: {exc.msg}")
        raise SystemExit(1) from None
    finally:
        connection.close()


if __name__ == "__main__":
    main()
