-- Independent of the model: the grain A plan rows of 2019-20 (without administration rows, none exist at grain A) on
-- their own keys, for the codes that exist as an organisation, a control budget detail and an economic budget in the
-- warehouse dimensions (the model cuts by those members).
SELECT p.organisation_code AS [Organisation Code], p.control_budget_detail AS [Control Budget Detail Code],
       CASE WHEN p.economic_budget = 'n/a' THEN 'NA' ELSE p.economic_budget END AS [Economic Budget],
       CAST(SUM(p.amount) AS decimal(38, 4)) AS [plan]
FROM dw.fact_plan AS p
WHERE p.financial_year = '2019-20' AND p.grain_code = 'A' AND p.is_part_of_other_measure = 0
  AND EXISTS (SELECT 1 FROM dw.dim_organisation AS o WHERE o.organisation_code = p.organisation_code)
  AND EXISTS (SELECT 1 FROM dw.dim_control_budget AS c WHERE c.control_budget_detail_code = p.control_budget_detail)
  AND EXISTS (SELECT 1 FROM dw.dim_account AS a WHERE a.economic_budget = CASE WHEN p.economic_budget = 'n/a' THEN 'NA' ELSE p.economic_budget END)
GROUP BY p.organisation_code, p.control_budget_detail, CASE WHEN p.economic_budget = 'n/a' THEN 'NA' ELSE p.economic_budget END
ORDER BY 1, 2, 3;
