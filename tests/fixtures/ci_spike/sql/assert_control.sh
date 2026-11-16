#!/usr/bin/env bash
# Compares raw.spend_line with the control file. Usage: assert_control.sh <label>
# Needs SQLCMDSERVER, SQLCMDUSER, SQLCMDPASSWORD and SQLCMDDBNAME in the environment
# (sqlcmd reads them, so the password never appears on a command line).
set -euo pipefail
label="$1"
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$here/spend_fixture.control"

# -C trusts the container's self-signed certificate; -h -1 -W -s '|' gives one bare row.
actual="$(sqlcmd -C -b -h -1 -W -s '|' -Q "SET NOCOUNT ON;
  SELECT COUNT(*),
         CONVERT(varchar(40), SUM(amount)),
         SUM(CASE WHEN description LIKE N'%' + NCHAR(163) + N'%' THEN 1 ELSE 0 END),
         SUM(CASE WHEN description LIKE N'%' + NCHAR(160) + N'%' THEN 1 ELSE 0 END)
  FROM raw.spend_line;" | head -n 1 | tr -d '\r')"
expected="${ROWS}|${SUM_AMOUNT}|${GBP_ROWS}|${NBSP_ROWS}"

echo "[$label] expected rows|sum|gbp_rows|nbsp_rows = $expected"
echo "[$label] actual                               = $actual"
if [[ "$actual" == "$expected" ]]; then
  echo "[$label] PASS"
else
  echo "::error::[$label] control totals do not match"
  exit 1
fi
