-- test: the four sign cases of the scenario comparison are real cells of OSCAR Plans against outturn, and each has the sign that the case names
-- marker: localdata
-- Spending is positive and income negative, so actual less plan below zero is favourable for both. A row is a problem: a
-- case whose plan or actual is missing, or whose variance has the wrong sign. Grain A rows need the OSCAR extracts.
WITH cases AS (
    SELECT * FROM (VALUES
        ('spending under plan', '2019-20', 'DFE022', 1, -1),
        ('spending over plan',   '2019-20', 'HOF034', 1,  1),
        ('income above plan',    '2019-20', 'XXX022', -1, -1),
        ('income below plan',    '2020-21', 'XXX022', -1,  1)
    ) AS c(case_name, fy, oc, plan_sign, variance_sign)
), pl AS (
    SELECT p.financial_year AS fy, p.organisation_code AS oc, SUM(p.amount) AS plan_amt
    FROM dw.fact_plan AS p
    WHERE p.grain_code = 'A' AND p.measure = 'RDEL'
    GROUP BY p.financial_year, p.organisation_code
), ac AS (
    SELECT d.financial_year AS fy, o.organisation_code AS oc, SUM(f.amount_delta) AS act_amt
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS d ON d.period_key = f.period_key
    JOIN dw.dim_organisation AS o ON o.organisation_key = f.organisation_key
    JOIN dw.dim_account AS a ON a.account_key = f.account_key
    JOIN dw.dim_control_budget AS cb ON cb.control_budget_key = f.control_budget_key
    WHERE cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN') AND a.economic_budget = 'RESOURCE'
    GROUP BY d.financial_year, o.organisation_code
)
SELECT c.case_name AS problem,
       CASE WHEN pl.plan_amt IS NULL OR ac.act_amt IS NULL THEN 'plan or actual missing'
            WHEN SIGN(pl.plan_amt) <> c.plan_sign THEN 'plan has the wrong sign'
            ELSE 'variance has the wrong sign' END AS detail
FROM cases AS c
LEFT JOIN pl ON pl.fy = c.fy AND pl.oc = c.oc
LEFT JOIN ac ON ac.fy = c.fy AND ac.oc = c.oc
WHERE pl.plan_amt IS NULL OR ac.act_amt IS NULL
   OR SIGN(pl.plan_amt) <> c.plan_sign
   OR SIGN(ac.act_amt - pl.plan_amt) <> c.variance_sign;
