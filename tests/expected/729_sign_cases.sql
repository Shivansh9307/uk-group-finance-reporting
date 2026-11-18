-- Independent of the model: the four cells, from the plan fact (grain A, resource DEL) and the outturn fact (DEL
-- programme and administration lines of resource economic categories, all releases), with the sign rule written out:
-- actual less plan below zero is favourable (indicator 1), above zero adverse (-1), zero on plan (0).
WITH cells AS (
    SELECT fy, oc FROM (VALUES ('2019-20', 'DFE022'), ('2019-20', 'HOF034'), ('2019-20', 'XXX022'), ('2020-21', 'XXX022')) AS c(fy, oc)
), pl AS (
    SELECT p.financial_year AS fy, p.organisation_code AS oc, SUM(p.amount) AS plan_amt
    FROM dw.fact_plan AS p JOIN cells AS c ON c.fy = p.financial_year AND c.oc = p.organisation_code
    WHERE p.grain_code = 'A' AND p.measure = 'RDEL'
    GROUP BY p.financial_year, p.organisation_code
), ac AS (
    SELECT d.financial_year AS fy, o.organisation_code AS oc, SUM(f.amount_delta) AS act_amt
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS d ON d.period_key = f.period_key
    JOIN dw.dim_organisation AS o ON o.organisation_key = f.organisation_key
    JOIN dw.dim_account AS a ON a.account_key = f.account_key
    JOIN dw.dim_control_budget AS cb ON cb.control_budget_key = f.control_budget_key
    JOIN cells AS c ON c.fy = d.financial_year AND c.oc = o.organisation_code
    WHERE cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN') AND a.economic_budget = 'RESOURCE'
    GROUP BY d.financial_year, o.organisation_code
), v AS (
    SELECT pl.fy, pl.oc, pl.plan_amt, ac.act_amt, ac.act_amt - pl.plan_amt AS variance
    FROM pl JOIN ac ON ac.fy = pl.fy AND ac.oc = pl.oc
), items AS (
    SELECT fy, oc, N'Actual' AS item, act_amt AS value FROM v
    UNION ALL SELECT fy, oc, N'Plan', plan_amt FROM v
    UNION ALL SELECT fy, oc, N'Variance', variance FROM v
    UNION ALL SELECT fy, oc, N'Variance %', variance * 1000000 / NULLIF(ABS(plan_amt), 0) FROM v
    UNION ALL SELECT fy, oc, N'Favourable/Adverse', CASE WHEN variance < 0 THEN 1 WHEN variance > 0 THEN -1 ELSE 0 END FROM v
)
SELECT fy AS [Financial Year], oc AS [Organisation Code], item AS [Comparison], CAST(value AS decimal(38, 6)) AS value
FROM items
ORDER BY fy, oc, item;
