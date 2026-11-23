-- test: for every release and every plan measure the in-year plan-basis outturn equals the matching selection of dw.fact_outturn (sum of the deltas of the release's financial year up to and including the release), in total and for each Spending Review group (the group the plan is published under: the bridge, except FY2022-23 outturn of BEIS, DCMS and DIT as reported, which is the combined group); the year-end rows are flagged, and the excluding-depreciation measures carry the basis note
WITH sel AS (
    SELECT r.release_key, r.financial_year, COALESCE(gr.plan_sr_group_key, b.sr_group_key) AS sr_group_key, m.measure, SUM(f.amount_delta) AS amount
    FROM dw.dim_release AS r
    JOIN dw.fact_outturn AS f ON f.release_key <= r.release_key
    JOIN dw.dim_period AS d ON d.period_key = f.period_key AND d.financial_year = r.financial_year
    JOIN dw.dim_segment AS sg ON sg.segment_key = f.segment_key
    JOIN dw.outturn_sr_group_bridge AS b ON b.organisation_key = f.organisation_key AND b.sub_segment_code = sg.sub_segment_code
    JOIN dw.dim_account AS a ON a.account_key = f.account_key
    JOIN dw.dim_control_budget AS cb ON cb.control_budget_key = f.control_budget_key
    JOIN dw.dim_department AS rd ON rd.department_key = f.department_key
    LEFT JOIN dw.plan_group_rule AS gr ON gr.financial_year = r.financial_year AND gr.department_number = rd.department_number
    CROSS APPLY (VALUES
        ('RDEL',          CASE WHEN cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN') AND a.economic_budget = 'RESOURCE' THEN 1 ELSE 0 END),
        ('RDEL_EX_DEPN',  CASE WHEN cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN') AND a.economic_budget = 'RESOURCE' AND a.pesa_economic_group_code <> 'DEPRECIATION' THEN 1 ELSE 0 END),
        ('CDEL',          CASE WHEN cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN') AND a.economic_budget = 'CAPITAL' THEN 1 ELSE 0 END),
        ('RAME',          CASE WHEN cb.control_budget_detail_code = 'DEPT AME' AND a.economic_budget = 'RESOURCE' THEN 1 ELSE 0 END),
        ('CAME',          CASE WHEN cb.control_budget_detail_code = 'DEPT AME' AND a.economic_budget = 'CAPITAL' THEN 1 ELSE 0 END),
        ('ADMIN',         CASE WHEN cb.control_budget_detail_code = 'DEL ADMIN' AND a.economic_budget = 'RESOURCE' THEN 1 ELSE 0 END),
        ('ADMIN_EX_DEPN', CASE WHEN cb.control_budget_detail_code = 'DEL ADMIN' AND a.economic_budget = 'RESOURCE' AND a.pesa_economic_group_code <> 'DEPRECIATION' THEN 1 ELSE 0 END)
    ) AS m (measure, selected)
    WHERE m.selected = 1
    GROUP BY r.release_key, r.financial_year, COALESCE(gr.plan_sr_group_key, b.sr_group_key), m.measure
), got AS (
    SELECT release_key, financial_year, sr_group_key, measure, SUM(amount) AS amount
    FROM dw.outturn_plan_basis_inyear
    GROUP BY release_key, financial_year, sr_group_key, measure
)
SELECT 'differs from the fact selection' AS problem, CAST(COALESCE(s.release_key, g.release_key) AS nvarchar(20)) AS detail,
       CAST(COALESCE(s.sr_group_key, g.sr_group_key) AS nvarchar(20)) AS detail2, COALESCE(s.measure, g.measure) AS detail3,
       CAST(s.amount AS nvarchar(40)) AS expected, CAST(g.amount AS nvarchar(40)) AS got
FROM sel AS s
FULL OUTER JOIN got AS g ON g.release_key = s.release_key AND g.sr_group_key = s.sr_group_key AND g.measure = s.measure
WHERE ISNULL(s.amount, 0) <> ISNULL(g.amount, 0)
UNION ALL
SELECT 'year-end flag differs from dim_release', CAST(b.release_key AS nvarchar(20)), NULL, NULL, NULL, NULL
FROM dw.outturn_plan_basis_inyear AS b
JOIN dw.dim_release AS r ON r.release_key = b.release_key
WHERE b.is_year_end_release <> r.is_year_end_release
UNION ALL
SELECT 'basis note missing or wrong', measure, NULL, NULL, NULL, NULL
FROM dw.outturn_plan_basis_inyear
WHERE (measure IN ('RDEL_EX_DEPN', 'ADMIN_EX_DEPN') AND basis_note NOT LIKE '%ringfence%')
   OR (measure NOT IN ('RDEL_EX_DEPN', 'ADMIN_EX_DEPN') AND basis_note LIKE '%ringfence column%')
GROUP BY measure
UNION ALL
SELECT 'year-end release total differs from the fact', r.label, NULL, 'RDEL+CDEL+RAME+CAME', CAST(x.a AS nvarchar(40)), CAST(y.a AS nvarchar(40))
FROM dw.dim_release AS r
CROSS APPLY (SELECT SUM(amount) AS a FROM dw.outturn_plan_basis_inyear
             WHERE release_key = r.release_key AND measure IN ('RDEL', 'CDEL', 'RAME', 'CAME')) AS x
CROSS APPLY (SELECT SUM(f.amount_delta) AS a
             FROM dw.fact_outturn AS f
             JOIN dw.dim_period AS d ON d.period_key = f.period_key AND d.financial_year = r.financial_year
             JOIN dw.dim_account AS a2 ON a2.account_key = f.account_key
             JOIN dw.dim_control_budget AS cb ON cb.control_budget_key = f.control_budget_key
             WHERE f.release_key <= r.release_key AND a2.economic_budget IN ('RESOURCE', 'CAPITAL')
               AND cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN', 'DEPT AME')) AS y
WHERE r.is_year_end_release = 1 AND ISNULL(x.a, 0) <> ISNULL(y.a, 0);
