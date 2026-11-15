# Event Management Project

This project has a Python backend and a separate receptionist-style menu CLI. MySQL handles booking totals, payment status, monthly revenue, progressive TDS estimates, generated net salary, checks, and foreign-key enforcement.

## Setup

1. Activate the Conda environment you want to use (for example `dsml`).
2. Install the Python dependencies with `python -m pip install -r requirements.txt`.
3. Check that the ignored `.env` file has `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, and `DB_NAME=event_management`.
4. Run `python setup_db.py`.
5. Start the operator menu with `python cli.py`.

`setup_db.py` creates missing tables, refreshes the SQL views, adds any missing foreign keys (including when upgrading a database made from the original DDL), and inserts the sample catalogue, clearly labelled demo customers/employees, four sample bookings, their service lines, and November 2026 payroll rows. It does not drop the database, clear tables, or replace existing catalogue values. The sample bookings include pending, partial, and paid states.

For a fresh database, the SQL can also be run manually in MySQL: run `SQL Files/ddl.sql`, then `SQL Files/sample_data.sql`. Use `setup_db.py` to upgrade a database made from the original DDL so it adds the missing foreign keys too.

## Operator menu

- **Bookings:** create a customer booking with one or more venue slots and service tiers, inspect the calculated total and dues, record a partial payment, enter actual service quantities, or cancel and release the venue slots. A booking and its slots/services are saved in one transaction.
- **Employees and payroll:** add, update, and remove employees, assign each employee to a service, preview the SQL tax estimate, and process payroll for one employee or all employees for a month. Payroll rows keep salary and deductions as a monthly snapshot; the database calculates net salary.
- **Venues and services:** maintain halls/lawns, slot rates, service categories, contracted-service flags, service tiers, and unit costs. Catering plate types are separate tiers; package-style services can be entered at quantity one.
- **Reports:** view active-booking revenue by month from the SQL view.

The database prevents deleting records that are still referenced by bookings or payroll history. Cancelled bookings remain in the booking history, while their reserved slots are released.

## Payroll model

The seeded 2026-27 progressive slabs use the new-regime income-tax rates: 0% through ₹4 lakh, then 5%, 10%, 15%, 20%, 25%, and 30% across the published bands. The project annualizes monthly salary, applies the slabs progressively, and divides by 12. The seeded employee PF deduction is 12% of the salary field because this schema has no separate basic-wage field.

As requested for the coursework model, this TDS estimate omits the rebate, cess, deductions, exemptions, and other income. The EPF percentage is applied to the whole `salary` column for demonstration, which is a simplification of the actual wage-base and eligibility rules. These values are editable in `fiscal_year`, `it_slab`, and `pf_rate`.

The slab bands follow the [Income Tax Department's Tax Year 2026-27 rates](https://www.incometax.gov.in/iec/foportal/help/all-topics/e-filing-services/itr-2/itr-2-faqs). EPFO documents the 12% contribution as the standard/default rate, while some establishments use 10%; this project seeds 12% for demonstration ([EPFO employer return manual](https://epfindia.gov.in/site_docs/PDFs/EReturnPDFs/USER%20MANUAL%20FOR%20EMPLOYERS.pdf)).

## Billing model

`vw_booking_cost` calculates `venue rate × booked slots + Σ(quantity × service-tier unit cost)`. It sums service charges separately so multiple slots do not multiply plate/package charges. The current venue and tier rates are used when the view is queried, so editing a rate also changes the displayed total for existing bookings.
