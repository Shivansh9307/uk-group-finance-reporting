-- test: audit.plan_variance_reconciliation has one row for every year x group x measure the plan or the in-year outturn has from FY2022-23, ties to dw.fact_plan and dw.outturn_plan_basis_inyear in total, each variance equals outturn less plan, the gaps add up to the variance, every row has a verdict, groups without outturn have none, and the unexplained cells are exactly the seven listed here (a change in the list is a change in the finding)
-- marker: localdata
-- requires: audit.plan_variance_reconciliation
WITH yrs AS (
    SELECT DISTINCT financial_year FROM dw.outturn_plan_basis_inyear WHERE is_year_end_release = 1 AND financial_year >= '2022-23'
), expected_plan AS (
    SELECT SUM(f.amount) AS s
    FROM dw.fact_plan AS f
    WHERE f.is_part_of_other_measure = 0 AND f.measure IN ('RDEL_EX_DEPN', 'CDEL', 'RAME', 'CAME') AND f.financial_year IN (SELECT financial_year FROM yrs)
), expected_out AS (
    SELECT SUM(b.amount) AS s
    FROM dw.outturn_plan_basis_inyear AS b
    WHERE b.is_year_end_release = 1 AND b.measure IN ('RDEL_EX_DEPN', 'CDEL', 'RAME', 'CAME') AND b.financial_year IN (SELECT financial_year FROM yrs)
), keys AS (
    SELECT COUNT(*) AS n FROM (
        SELECT f.financial_year, f.sr_group_key, f.measure FROM dw.fact_plan AS f
        WHERE f.is_part_of_other_measure = 0 AND f.measure IN ('RDEL_EX_DEPN', 'CDEL', 'RAME', 'CAME') AND f.financial_year IN (SELECT financial_year FROM yrs)
        UNION
        SELECT b.financial_year, b.sr_group_key, b.measure FROM dw.outturn_plan_basis_inyear AS b
        WHERE b.is_year_end_release = 1 AND b.measure IN ('RDEL_EX_DEPN', 'CDEL', 'RAME', 'CAME') AND b.financial_year IN (SELECT financial_year FROM yrs)
    ) AS u
), got AS (
    SELECT SUM(plan_amount) AS p, SUM(outturn) AS o, COUNT(*) AS n FROM audit.plan_variance_reconciliation
), pinned AS (
    SELECT financial_year, sr_group_code, measure FROM (VALUES
        ('2022-23', 'SR_003', 'RAME'), ('2022-23', 'SR_047', 'RAME'), ('2022-23', 'SR_COM', 'RDEL_EX_DEPN'),
        ('2023-24', 'SR_013', 'CDEL'), ('2023-24', 'SR_030', 'RAME'), ('2024-25', 'SR_003', 'RAME'), ('2024-25', 'SR_013', 'RAME')
    ) AS v (financial_year, sr_group_code, measure)
)
SELECT 'plan total differs from dw.fact_plan' AS problem, CONCAT(g.p, ' against ', e.s) AS detail
FROM got AS g CROSS JOIN expected_plan AS e WHERE g.p <> e.s
UNION ALL
SELECT 'outturn total differs from the in-year plan-basis table', CONCAT(g.o, ' against ', e.s)
FROM got AS g CROSS JOIN expected_out AS e WHERE g.o <> e.s
UNION ALL
SELECT 'row count differs from the distinct cells of the plan and the outturn', CONCAT(g.n, ' against ', k.n)
FROM got AS g CROSS JOIN keys AS k WHERE g.n <> k.n
UNION ALL
SELECT 'variance is not outturn less plan', CONCAT(financial_year, ' ', sr_group_code, ' ', measure)
FROM audit.plan_variance_reconciliation WHERE variance <> outturn - plan_amount
UNION ALL
SELECT 'gaps do not add up to the variance', CONCAT(financial_year, ' ', sr_group_code, ' ', measure)
FROM audit.plan_variance_reconciliation
WHERE outturn_reference IS NOT NULL AND gap_plan_only = 0 AND gap_outturn_only = 0 AND variance <> gap_first_look + gap_on_reference
UNION ALL
SELECT 'plan-only or outturn-only variance is not in its own gap', CONCAT(financial_year, ' ', sr_group_code, ' ', measure)
FROM audit.plan_variance_reconciliation
WHERE (gap_plan_only <> 0 AND variance <> gap_plan_only) OR (gap_outturn_only <> 0 AND variance <> gap_outturn_only)
UNION ALL
SELECT 'row without a verdict', CONCAT(financial_year, ' ', sr_group_code, ' ', measure)
FROM audit.plan_variance_reconciliation
WHERE verdict IS NULL OR verdict = '' OR verdict_class NOT IN ('ok', 'fixed', 'explained', 'unexplained')
UNION ALL
SELECT 'group without outturn has outturn', CONCAT(r.financial_year, ' ', r.sr_group_code, ' ', r.measure)
FROM audit.plan_variance_reconciliation AS r
JOIN dw.dim_sr_group AS g ON g.sr_group_code = r.sr_group_code
WHERE g.has_outturn = 0 AND r.outturn <> 0
UNION ALL
SELECT 'unexplained cell not in the pinned list', CONCAT(r.financial_year, ' ', r.sr_group_code, ' ', r.measure)
FROM audit.plan_variance_reconciliation AS r
WHERE r.verdict_class = 'unexplained'
  AND NOT EXISTS (SELECT 1 FROM pinned AS p WHERE p.financial_year = r.financial_year AND p.sr_group_code = r.sr_group_code AND p.measure = r.measure)
UNION ALL
SELECT 'pinned unexplained cell is no longer unexplained', CONCAT(p.financial_year, ' ', p.sr_group_code, ' ', p.measure)
FROM pinned AS p
WHERE NOT EXISTS (SELECT 1 FROM audit.plan_variance_reconciliation AS r
                  WHERE r.financial_year = p.financial_year AND r.sr_group_code = p.sr_group_code AND r.measure = p.measure
                    AND r.verdict_class = 'unexplained')
UNION ALL
SELECT 'unexplained cell has a variance of 1bn or more', CONCAT(financial_year, ' ', sr_group_code, ' ', measure)
FROM audit.plan_variance_reconciliation WHERE verdict_class = 'unexplained' AND ABS(variance) >= 1000000;
