-- Independent of the model: the five quantities of the cell (actual and plan for 2020-21 and 2019-20, and the actual of
-- period 12, of periods 10 to 12 and of the twelve allocated months), then the 40 combinations written out by rule.
-- Plan exists only for a whole year, so MTD, QTD and Rolling 12 months have no plan. Variance is actual less plan, the
-- percentage divides by the absolute plan, the indicator is 1 below zero, -1 above zero, 0 at zero.
WITH pl AS (
    SELECT p.financial_year AS fy, SUM(p.amount) AS plan_amt
    FROM dw.fact_plan AS p
    WHERE p.grain_code = 'A' AND p.measure = 'RDEL' AND p.organisation_code = 'DFE022' AND p.financial_year IN ('2019-20', '2020-21')
    GROUP BY p.financial_year
), ac AS (
    SELECT d.financial_year AS fy, d.period, f.amount_delta
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS d ON d.period_key = f.period_key
    JOIN dw.dim_organisation AS o ON o.organisation_key = f.organisation_key
    JOIN dw.dim_account AS a ON a.account_key = f.account_key
    JOIN dw.dim_control_budget AS cb ON cb.control_budget_key = f.control_budget_key
    WHERE o.organisation_code = 'DFE022' AND cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN')
      AND a.economic_budget = 'RESOURCE' AND d.financial_year IN ('2019-20', '2020-21')
), q AS (
    SELECT
        (SELECT SUM(plan_amt) FROM pl WHERE fy = '2020-21') AS p2,
        (SELECT SUM(plan_amt) FROM pl WHERE fy = '2019-20') AS p1,
        (SELECT SUM(amount_delta) FROM ac WHERE fy = '2020-21') AS a2,
        (SELECT SUM(amount_delta) FROM ac WHERE fy = '2019-20') AS a1,
        (SELECT SUM(amount_delta) FROM ac WHERE fy = '2020-21' AND period = 12) AS a_mtd,
        (SELECT SUM(amount_delta) FROM ac WHERE fy = '2020-21' AND period BETWEEN 10 AND 12) AS a_qtd,
        (SELECT SUM(amount_delta) FROM ac WHERE fy = '2020-21' AND period BETWEEN 1 AND 12) AS a_r12
), ti AS (
    SELECT t.name AS ti FROM (VALUES (N'Current'), (N'MTD'), (N'QTD'), (N'YTD'), (N'PY'), (N'YoY'), (N'YoY %'), (N'Rolling 12 months')) AS t(name)
), sc AS (
    SELECT s.name AS sc FROM (VALUES (N'Actual'), (N'Plan'), (N'Variance'), (N'Variance %'), (N'Favourable/Adverse')) AS s(name)
), w AS (
    -- the window of each plain item: actual and plan in it (plan is NULL below the grain of a plan)
    SELECT ti.ti, sc.sc,
           CASE ti.ti WHEN N'Current' THEN q.a2 WHEN N'YTD' THEN q.a2 WHEN N'PY' THEN q.a1 WHEN N'MTD' THEN q.a_mtd
                      WHEN N'QTD' THEN q.a_qtd WHEN N'Rolling 12 months' THEN q.a_r12 END AS a,
           CASE ti.ti WHEN N'Current' THEN q.p2 WHEN N'YTD' THEN q.p2 WHEN N'PY' THEN q.p1 END AS p,
           q.a2, q.p2, q.a1, q.p1
    FROM ti CROSS JOIN sc CROSS JOIN q
), r AS (
    SELECT ti, sc,
        CASE
            WHEN ti = N'YoY' THEN
                CASE sc WHEN N'Actual' THEN a2 - a1 WHEN N'Plan' THEN p2 - p1 WHEN N'Variance' THEN (a2 - p2) - (a1 - p1) END
            WHEN ti = N'YoY %' THEN
                CASE sc WHEN N'Actual' THEN (a2 - a1) * 1000000 / NULLIF(ABS(a1), 0)
                        WHEN N'Plan' THEN (p2 - p1) * 1000000 / NULLIF(ABS(p1), 0)
                        WHEN N'Variance' THEN ((a2 - p2) - (a1 - p1)) * 1000000 / NULLIF(ABS(a1 - p1), 0) END
            ELSE
                CASE sc WHEN N'Actual' THEN a
                        WHEN N'Plan' THEN p
                        WHEN N'Variance' THEN a - p
                        WHEN N'Variance %' THEN (a - p) * 1000000 / NULLIF(ABS(p), 0)
                        WHEN N'Favourable/Adverse' THEN CASE WHEN a - p < 0 THEN 1 WHEN a - p > 0 THEN -1 WHEN a - p = 0 THEN 0 END
                END
        END AS value
    FROM w
)
SELECT ti AS [Time Calculation], sc AS [Comparison], CAST(value AS decimal(38, 6)) AS value
FROM r
WHERE value IS NOT NULL
ORDER BY ti, sc;
