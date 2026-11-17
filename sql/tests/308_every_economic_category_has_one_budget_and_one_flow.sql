-- test: every economic category has exactly one economic budget and one income / expenditure value, the budget is the one the latest release gives, and no category is left unclassified
SELECT a.economic_category_code AS code, 'budget or flow missing or not allowed' AS problem
FROM dw.dim_account AS a
WHERE a.account_key <> -1
  AND (a.economic_budget IS NULL OR a.economic_budget = N''
       OR a.flow NOT IN ('Expenditure', 'Income', 'Not applicable')
       OR a.flow_basis NOT IN ('authored', 'digit rule'))
UNION ALL
SELECT a.economic_category_code, 'economic budget differs from the latest release that reports the category'
FROM dw.dim_account AS a
WHERE a.account_key <> -1
  AND EXISTS (
      SELECT 1 FROM stg.inyear_snapshot AS s
      WHERE CASE WHEN s.economic_category_code = 'n/a' THEN 'NA' ELSE s.economic_category_code END = a.economic_category_code
        AND s.release = a.last_release AND s.economic_budget_code <> a.economic_budget)
UNION ALL
SELECT x.code, 'more than one economic budget in the data outside the NA relabel (' + CAST(x.n AS varchar(5)) + ' values)'
FROM (
    SELECT CASE WHEN economic_category_code = 'n/a' THEN 'NA' ELSE economic_category_code END AS code,
           COUNT(DISTINCT economic_budget_code) AS n
    FROM stg.inyear_snapshot
    GROUP BY CASE WHEN economic_category_code = 'n/a' THEN 'NA' ELSE economic_category_code END
    HAVING COUNT(DISTINCT economic_budget_code) > 1
) AS x
WHERE x.code <> 'NA'
UNION ALL
SELECT a.economic_category_code, 'digit rule gave a value that disagrees with the code'
FROM dw.dim_account AS a
WHERE a.account_key <> -1 AND a.flow_basis = 'digit rule'
  AND NOT ((RIGHT(a.economic_category_code, 1) = '1' AND a.flow = 'Expenditure') OR (RIGHT(a.economic_category_code, 1) = '2' AND a.flow = 'Income'))
UNION ALL
SELECT s.code, 'category in the data has no row in dim_account'
FROM (SELECT DISTINCT CASE WHEN economic_category_code = 'n/a' THEN 'NA' ELSE economic_category_code END AS code FROM stg.inyear_snapshot) AS s
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_account AS a WHERE a.economic_category_code = s.code)
UNION ALL
SELECT 'authored row ' + CAST(f.flow_id AS varchar(10)), 'authored flow not used'
FROM stg.account_flow AS f
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_account AS a WHERE a.economic_category_code = f.economic_category_code AND a.flow = f.flow AND a.flow_basis = 'authored');
