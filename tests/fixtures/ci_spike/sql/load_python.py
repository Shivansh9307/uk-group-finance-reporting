"""Load the CSV fixture into raw.spend_line through a Python driver, then check control totals.

Usage: python load_python.py pyodbc|mssql-python <csv> <control file>
Connection details come from SQLCMDSERVER, SQLCMDUSER, SQLCMDPASSWORD and SQLCMDDBNAME.
"""

import csv
import os
import sys
import time
from decimal import Decimal

driver, csv_path, control_path = sys.argv[1], sys.argv[2], sys.argv[3]
server = os.environ["SQLCMDSERVER"]
database = os.environ["SQLCMDDBNAME"]
user = os.environ["SQLCMDUSER"]
password = os.environ["SQLCMDPASSWORD"]

with open(csv_path, encoding="utf-8", newline="") as fh:
    reader = csv.DictReader(fh)
    rows = [(int(r["line_id"]), r["department"], r["description"], Decimal(r["amount"])) for r in reader]

if driver == "pyodbc":
    import pyodbc

    conn = pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={server};DATABASE={database};"
        f"UID={user};PWD={password};Encrypt=yes;TrustServerCertificate=yes",
        autocommit=False,
    )
elif driver == "mssql-python":
    import mssql_python

    conn = mssql_python.connect(
        f"Server={server};Database={database};UID={user};PWD={password};"
        "Encrypt=yes;TrustServerCertificate=yes"
    )
else:
    raise SystemExit(f"unknown driver {driver}")

cur = conn.cursor()
cur.execute("TRUNCATE TABLE raw.spend_line")
if driver == "pyodbc":
    cur.fast_executemany = True
started = time.perf_counter()
cur.executemany(
    "INSERT INTO raw.spend_line (line_id, department, description, amount) VALUES (?, ?, ?, ?)", rows
)
conn.commit()
elapsed = time.perf_counter() - started

cur.execute(
    "SELECT COUNT(*), SUM(amount),"
    " SUM(CASE WHEN description LIKE N'%' + NCHAR(163) + N'%' THEN 1 ELSE 0 END),"
    " SUM(CASE WHEN description LIKE N'%' + NCHAR(160) + N'%' THEN 1 ELSE 0 END)"
    " FROM raw.spend_line"
)
count, total, gbp, nbsp = cur.fetchone()
conn.close()

control = dict(line.split("=", 1) for line in open(control_path, encoding="utf-8").read().split())
expected = (int(control["ROWS"]), Decimal(control["SUM_AMOUNT"]), int(control["GBP_ROWS"]), int(control["NBSP_ROWS"]))
actual = (count, Decimal(total), gbp, nbsp)
print(f"[{driver}] inserted {len(rows)} rows in {elapsed:.2f}s")
print(f"[{driver}] expected {expected}")
print(f"[{driver}] actual   {actual}")
if actual != expected:
    print(f"::error::[{driver}] control totals do not match")
    sys.exit(1)
print(f"[{driver}] PASS")
