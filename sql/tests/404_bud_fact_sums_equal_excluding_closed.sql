-- test: dw.fact_outturn_annual sums to amount_sum_excluding_closed for each workbook, and holds every non-Closed row
-- marker: localdata
-- requires: dw.fact_outturn_annual, raw.oscar_bud_control_expected
SELECT e.vintage, e.filename, x.fact_sum, e.amount_sum_excluding_closed AS expected_sum,
       x.source_rows AS fact_source_rows, e.data_rows - e.closed_rows AS expected_rows
FROM raw.oscar_bud_control_expected AS e
LEFT JOIN (
    SELECT vintage, financial_year, SUM(amount) AS fact_sum, SUM(CAST(source_rows AS bigint)) AS source_rows
    FROM dw.fact_outturn_annual GROUP BY vintage, financial_year
) AS x ON x.vintage = e.vintage AND x.financial_year = e.financial_year
WHERE x.fact_sum IS NULL
   OR x.fact_sum <> e.amount_sum_excluding_closed
   OR x.source_rows <> e.data_rows - e.closed_rows;
