-- Independent of the model: the outturn fact joined to its dimensions and, through the outturn-to-group bridge, to the
-- Spending Review group, for the (year, group, measure) cells that have a plan row. Every release of the year is
-- summed, which is the latest view of the year.
WITH o AS (
    SELECT d.financial_year, b.sr_group_key, m.measure, SUM(f.amount_delta) AS amt
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS d ON d.period_key = f.period_key
    JOIN dw.dim_segment AS s ON s.segment_key = f.segment_key
    JOIN dw.outturn_sr_group_bridge AS b ON b.organisation_key = f.organisation_key AND b.sub_segment_code = s.sub_segment_code
    JOIN dw.dim_account AS a ON a.account_key = f.account_key
    JOIN dw.dim_control_budget AS cb ON cb.control_budget_key = f.control_budget_key
    CROSS APPLY (
        SELECT N'NON_DEPT_AME' AS measure WHERE cb.control_budget_detail_code = 'NON-DEPT AME'
        UNION ALL SELECT N'NON_BUDGET' WHERE cb.control_budget_detail_code = 'NON-BUDGET'
        UNION ALL SELECT N'UNCLASSIFIED' WHERE cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN', 'DEPT AME')
                                           AND a.economic_budget NOT IN ('RESOURCE', 'CAPITAL')
    ) AS m
    GROUP BY d.financial_year, b.sr_group_key, m.measure
)
SELECT o.financial_year AS [Financial Year], g.sr_group_name AS [Spending Review Group], o.measure AS [Plan Measure],
       CAST(o.amt AS decimal(38, 4)) AS basis
FROM o
JOIN dw.dim_sr_group AS g ON g.sr_group_key = o.sr_group_key
WHERE EXISTS (SELECT 1 FROM dw.fact_plan AS p WHERE p.financial_year = o.financial_year AND p.sr_group_key = o.sr_group_key AND p.measure = o.measure)
ORDER BY o.financial_year, g.sr_group_name, o.measure;
