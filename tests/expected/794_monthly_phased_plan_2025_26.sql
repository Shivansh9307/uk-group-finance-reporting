-- Independent of the model: the plan-basis table and the phased plan, by period, for 2025-26.
SELECT p.period_no AS period, CAST(b.amount AS decimal(38, 4)) AS outturn_plan_basis, CAST(p.amount AS decimal(38, 4)) AS phased_plan,
       CAST(b.amount - p.amount AS decimal(38, 4)) AS variance
FROM (SELECT period_no, SUM(amount) AS amount FROM dw.fact_plan_phased
      WHERE financial_year = '2025-26' AND is_part_of_other_measure = 0 AND period_no >= 1 GROUP BY period_no) AS p
JOIN (SELECT period_no, SUM(amount) AS amount FROM dw.outturn_plan_basis_inyear
      WHERE financial_year = '2025-26' AND period_no >= 1
        AND release_key = (SELECT MAX(release_key) FROM dw.dim_release WHERE financial_year = '2025-26')
        AND measure IN (SELECT DISTINCT measure FROM dw.fact_plan WHERE financial_year = '2025-26' AND is_part_of_other_measure = 0)
      GROUP BY period_no) AS b ON b.period_no = p.period_no
ORDER BY p.period_no;
