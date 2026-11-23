-- requires: audit.plan_variance_reconciliation
-- Independent of the model: the plan and the in-year plan-basis outturn at the closing release of each year from 2022-23,
-- summed over the Spending Review groups, by plan measure (administration is part of resource DEL and is left out).
SELECT p.financial_year, p.measure,
       CAST(p.amount AS decimal(38, 4)) AS plan_amount, CAST(b.amount AS decimal(38, 4)) AS outturn,
       CAST(b.amount - p.amount AS decimal(38, 4)) AS variance
FROM (SELECT financial_year, measure, SUM(amount) AS amount FROM dw.fact_plan
      WHERE is_part_of_other_measure = 0 AND measure IN ('RDEL_EX_DEPN', 'CDEL', 'RAME', 'CAME')
        AND financial_year IN ('2022-23', '2023-24', '2024-25', '2025-26')
      GROUP BY financial_year, measure) AS p
JOIN (SELECT b2.financial_year, b2.measure, SUM(b2.amount) AS amount FROM dw.outturn_plan_basis_inyear AS b2
      WHERE b2.measure IN ('RDEL_EX_DEPN', 'CDEL', 'RAME', 'CAME')
        AND b2.release_key = (SELECT MAX(r.release_key) FROM dw.dim_release AS r WHERE r.financial_year = b2.financial_year)
      GROUP BY b2.financial_year, b2.measure) AS b ON b.financial_year = p.financial_year AND b.measure = p.measure
ORDER BY p.financial_year, p.measure;
