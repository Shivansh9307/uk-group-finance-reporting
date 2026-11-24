-- test: audit.forecast_r13_vs_outturn covers FY2018-19 to FY2022-23 against both the annual vintages that hold the year and the year-end in-year release, its R13 total equals the independent recomputation of R13 months 1 to 12, and every gap is the difference of its two amounts (a comparison, not a gate: the size of the gaps is explained in the data dictionary)
-- marker: localdata
-- requires: audit.forecast_r13_vs_outturn, raw.forecast_return_expected
SELECT 'year without an in-year comparison' AS problem, y.financial_year AS detail
FROM (VALUES ('2018-19'), ('2019-20'), ('2020-21'), ('2021-22'), ('2022-23')) AS y (financial_year)
WHERE NOT EXISTS (SELECT 1 FROM audit.forecast_r13_vs_outturn AS a WHERE a.financial_year = y.financial_year AND a.source LIKE 'in-year %')
UNION ALL
SELECT 'year without an annual comparison', y.financial_year
FROM (VALUES ('2018-19'), ('2019-20'), ('2020-21'), ('2021-22'), ('2022-23')) AS y (financial_year)
WHERE NOT EXISTS (SELECT 1 FROM audit.forecast_r13_vs_outturn AS a WHERE a.financial_year = y.financial_year AND a.source LIKE 'annual %')
UNION ALL
SELECT 'level missing for a source', a.financial_year + ' ' + a.source
FROM audit.forecast_r13_vs_outturn AS a
GROUP BY a.financial_year, a.source
HAVING COUNT(*) <> 5
UNION ALL
SELECT 'gap is not r13 minus the other source', a.financial_year + ' ' + a.source + ' ' + a.level
FROM audit.forecast_r13_vs_outturn AS a WHERE a.gap <> a.r13_amount - a.other_amount
UNION ALL
SELECT 'R13 total differs from the independent recomputation', a.financial_year + ' ' + a.source
FROM audit.forecast_r13_vs_outturn AS a
JOIN (SELECT financial_year, SUM(CAST(amount_sum AS decimal(38, 16))) AS amount, SUM(data_rows) AS n
      FROM raw.forecast_return_expected WHERE return_no = 13 AND period BETWEEN 1 AND 12 GROUP BY financial_year) AS e
  ON e.financial_year = a.financial_year
WHERE a.level = 'TOTAL' AND ABS(a.r13_amount - e.amount) > 0.0001 + 0.00005 * e.n;
