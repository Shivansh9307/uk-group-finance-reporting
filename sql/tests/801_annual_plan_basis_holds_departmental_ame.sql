-- test: dw.outturn_plan_basis_annual holds departmental resource AME and capital AME as well as DEL, and each vintage and year adds up to the control budget detail DEPT AME of the annual file (it had no AME before, so a variance on AME could not be set against the final outturn)
-- marker: localdata
-- requires: dw.outturn_plan_basis_annual, dw.fact_outturn_annual
WITH a AS (
    SELECT vintage, financial_year, measure, SUM(amount) AS amount
    FROM dw.outturn_plan_basis_annual WHERE measure IN ('RAME', 'CAME')
    GROUP BY vintage, financial_year, measure
), f AS (
    SELECT vintage, financial_year,
           CASE economic_budget_code WHEN 'RESOURCE' THEN 'RAME' ELSE 'CAME' END AS measure, SUM(amount) AS amount
    FROM dw.fact_outturn_annual
    WHERE control_budget_detail_code = 'DEPT AME' AND economic_budget_code IN ('RESOURCE', 'CAPITAL')
    GROUP BY vintage, financial_year, CASE economic_budget_code WHEN 'RESOURCE' THEN 'RAME' ELSE 'CAME' END
)
SELECT 'AME of the annual basis table differs from the annual file' AS problem,
       COALESCE(a.vintage, f.vintage) + ' ' + COALESCE(a.financial_year, f.financial_year) + ' ' + COALESCE(a.measure, f.measure) AS detail,
       CONCAT(a.amount, ' against ', f.amount) AS detail2
FROM a
FULL OUTER JOIN f ON f.vintage = a.vintage AND f.financial_year = a.financial_year AND f.measure = a.measure
WHERE ISNULL(a.amount, 0) <> ISNULL(f.amount, 0);
