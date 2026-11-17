-- test: dw.fact_plan has one row per plan source, year, group, organisation, control budget detail, economic budget and measure; the grain code agrees with the plan source and the years; organisation is set only at grain A and each organisation sits in one group per year
SELECT CAST(plan_source_key AS varchar(10)) AS k1, financial_year AS k2, CAST(sr_group_key AS varchar(10)) AS k3, measure AS k4, 'duplicate natural key' AS problem
FROM dw.fact_plan
GROUP BY plan_source_key, financial_year, sr_group_key, organisation_code, control_budget_detail, economic_budget, measure
HAVING COUNT(*) > 1
UNION ALL
SELECT CAST(f.plan_fact_key AS varchar(10)), f.financial_year, f.grain_code, s.family, 'grain code does not fit the plan source family'
FROM dw.fact_plan AS f JOIN dw.dim_plan_source AS s ON s.plan_source_key = f.plan_source_key
WHERE (f.grain_code = 'A' AND s.family <> 'oscar_extract')
   OR (f.grain_code IN ('B', 'C') AND s.family <> 'estimates')
   OR (f.grain_code = 'D' AND s.family <> 'pesa')
UNION ALL
SELECT CAST(plan_fact_key AS varchar(10)), financial_year, grain_code, organisation_code, 'organisation must be set at grain A and NULL elsewhere'
FROM dw.fact_plan
WHERE (grain_code = 'A' AND organisation_code IS NULL) OR (grain_code <> 'A' AND organisation_code IS NOT NULL)
UNION ALL
SELECT CAST(plan_fact_key AS varchar(10)), financial_year, grain_code, NULL, 'year outside the years of the grain'
FROM dw.fact_plan
WHERE (grain_code = 'A' AND financial_year NOT IN ('2017-18', '2018-19', '2019-20', '2020-21', '2021-22'))
   OR (grain_code = 'B' AND financial_year NOT IN ('2023-24', '2024-25', '2025-26', '2026-27'))
   OR (grain_code = 'C' AND financial_year <> '2022-23')
   OR (grain_code = 'D' AND financial_year NOT IN ('2022-23', '2023-24', '2024-25', '2025-26', '2026-27', '2027-28', '2028-29'))
UNION ALL
SELECT NULL, financial_year, organisation_code, NULL, 'organisation is in more than one Spending Review group in one year'
FROM dw.fact_plan WHERE grain_code = 'A'
GROUP BY financial_year, organisation_code HAVING COUNT(DISTINCT sr_group_key) > 1
UNION ALL
SELECT NULL, financial_year, NULL, NULL, 'more than one Estimates workbook feeds the year'
FROM dw.fact_plan AS f JOIN dw.dim_plan_source AS s ON s.plan_source_key = f.plan_source_key
WHERE s.family = 'estimates'
GROUP BY financial_year HAVING COUNT(DISTINCT f.plan_source_key) > 1
UNION ALL
SELECT NULL, f.financial_year, CASE WHEN f.measure IN ('ADMIN', 'ADMIN_EX_DEPN') THEN 'ADMIN' ELSE f.measure END, NULL,
       'more than one PESA edition feeds the year and kind of budget'
FROM dw.fact_plan AS f JOIN dw.dim_plan_source AS s ON s.plan_source_key = f.plan_source_key
WHERE s.family = 'pesa'
GROUP BY f.financial_year, CASE WHEN f.measure IN ('ADMIN', 'ADMIN_EX_DEPN') THEN 'ADMIN' ELSE f.measure END
HAVING COUNT(DISTINCT f.plan_source_key) > 1;
