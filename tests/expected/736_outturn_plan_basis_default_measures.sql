-- Independent of the model: the in-year plan-basis table at the closing release of each year, summed over the
-- measures that have a plan row in the year and group, leaving out ADMIN and ADMIN_EX_DEPN (part of resource DEL).
SELECT b.financial_year AS [Financial Year], g.sr_group_name AS [Spending Review Group],
       CAST(SUM(b.amount) AS decimal(38, 4)) AS basis
FROM dw.outturn_plan_basis_inyear AS b
JOIN dw.dim_sr_group AS g ON g.sr_group_key = b.sr_group_key
WHERE b.financial_year IN ('2022-23', '2023-24', '2024-25', '2025-26')
  AND b.measure NOT IN ('ADMIN', 'ADMIN_EX_DEPN')
  AND b.release_key = (SELECT MAX(r.release_key) FROM dw.dim_release AS r WHERE r.financial_year = b.financial_year)
  AND EXISTS (SELECT 1 FROM dw.fact_plan AS p
              WHERE p.financial_year = b.financial_year AND p.sr_group_key = b.sr_group_key AND p.measure = b.measure
                AND p.is_part_of_other_measure = 0)
GROUP BY b.financial_year, g.sr_group_name
ORDER BY b.financial_year, g.sr_group_name;
