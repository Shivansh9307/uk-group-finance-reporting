-- test: no plan row carries a FLOAT or an unconverted unit: every cell with a value has a recognised unit and a converted amount, the multiplier is the one the unit text implies, and fact amounts are DECIMAL(19,4)
SELECT 'estimates' AS source, edition, sheet, unit, 'value without a converted amount' AS problem
FROM stg.plan_estimates_line WHERE value_published IS NOT NULL AND (unit_multiplier IS NULL OR amount_k IS NULL)
GROUP BY edition, sheet, unit
UNION ALL
SELECT 'pesa', edition, sheet, unit, 'value without a converted amount'
FROM stg.plan_pesa_line WHERE value_published IS NOT NULL AND (unit_multiplier IS NULL OR amount_k IS NULL)
GROUP BY edition, sheet, unit
UNION ALL
SELECT 'estimates', edition, sheet, unit, 'amount_k is not value x multiplier to 4 decimal places'
FROM stg.plan_estimates_line WHERE value_published IS NOT NULL AND ABS(amount_k - value_published * unit_multiplier) > 0.00005
GROUP BY edition, sheet, unit
UNION ALL
SELECT 'pesa', edition, sheet, unit, 'amount_k is not value x multiplier to 4 decimal places'
FROM stg.plan_pesa_line WHERE value_published IS NOT NULL AND ABS(amount_k - value_published * unit_multiplier) > 0.00005
GROUP BY edition, sheet, unit
UNION ALL
SELECT 'estimates', edition, sheet, unit, 'billion must convert x 1,000,000 and million x 1,000'
FROM stg.plan_estimates_line
WHERE (LOWER(unit) LIKE '%billion%' AND unit_multiplier <> 1000000) OR (LOWER(unit) LIKE '%million%' AND unit_multiplier <> 1000)
GROUP BY edition, sheet, unit
UNION ALL
SELECT 'pesa', edition, sheet, unit, 'billion must convert x 1,000,000 and million x 1,000'
FROM stg.plan_pesa_line
WHERE (LOWER(unit) LIKE '%billion%' AND unit_multiplier <> 1000000) OR (LOWER(unit) LIKE '%million%' AND unit_multiplier <> 1000)
GROUP BY edition, sheet, unit
UNION ALL
SELECT 'fact_plan', 'amount', NULL, ty.name + '(' + CAST(c.precision AS varchar(3)) + ',' + CAST(c.scale AS varchar(3)) + ')', 'amount must be decimal(19,4)'
FROM sys.columns AS c
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID(N'dw.fact_plan') AND c.name = 'amount'
  AND NOT (ty.name = 'decimal' AND c.precision = 19 AND c.scale = 4)
UNION ALL
SELECT s.name + '.' + t.name, c.name, NULL, ty.name, 'plan table column is float, real or money'
FROM sys.columns AS c
JOIN sys.tables AS t ON t.object_id = c.object_id
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE ty.name IN ('float', 'real', 'money', 'smallmoney')
  AND (t.name LIKE 'plan[_]%' OR t.name LIKE '%[_]plan' OR t.name LIKE 'dim[_]plan[_]%' OR t.name LIKE 'dim[_]sr[_]group');
