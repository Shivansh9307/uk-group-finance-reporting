-- test: the authored cash-flow map has a row for every line of the three statements and for no other code; a derived input is a line, never a subtotal or a total, with the factor its kind needs (an asset or a liability -1, equity +1, an income-statement flow +1 into its section and -1 out of the reserve movement, once each); every balance-sheet line other than cash feeds the derived cash flow exactly once; a published line is compared with a derived line of its own section; every derived line is used
-- marker: localdata
-- requires: dw.tac_cash_flow_line, dw.tac_cash_flow_comparison, stg.tac_cash_flow_map
SELECT l.sub_code AS code, 'statement line with no row in the map' AS problem
FROM dw.tac_statutory_line AS l
WHERE NOT EXISTS (SELECT 1 FROM stg.tac_cash_flow_map AS m WHERE m.sub_code = l.sub_code)
UNION ALL
SELECT m.sub_code, 'map row for a code that is not a statement line'
FROM stg.tac_cash_flow_map AS m
WHERE NOT EXISTS (SELECT 1 FROM dw.tac_statutory_line AS l WHERE l.sub_code = m.sub_code AND l.statement = m.statement)
UNION ALL
SELECT m.sub_code, 'a derive or compare row on a subtotal or a total'
FROM stg.tac_cash_flow_map AS m
JOIN dw.tac_statutory_line AS l ON l.sub_code = m.sub_code
WHERE m.treatment IN ('derive', 'compare') AND l.line_kind <> 'line'
UNION ALL
SELECT m.sub_code, 'a subtotal or total that is not marked not_used or result'
FROM stg.tac_cash_flow_map AS m
JOIN dw.tac_statutory_line AS l ON l.sub_code = m.sub_code
WHERE l.line_kind <> 'line' AND m.treatment NOT IN ('not_used', 'result')
UNION ALL
-- a balance-sheet input: movement, factor -1 for the asset and liability blocks, +1 for equity
SELECT m.sub_code, 'balance-sheet input with the wrong basis or factor'
FROM stg.tac_cash_flow_map AS m
JOIN dw.tac_statutory_line AS l ON l.sub_code = m.sub_code
WHERE m.treatment = 'derive' AND m.statement = 'SoFP'
  AND NOT (m.basis = 'movement' AND m.factor = CASE WHEN l.section = N'Taxpayers'' equity' THEN 1 ELSE -1 END)
UNION ALL
SELECT l.sub_code, 'balance-sheet line that does not feed the derived cash flow exactly once (cash is the result and feeds none)'
FROM dw.tac_statutory_line AS l
WHERE l.statement = 'SoFP' AND l.line_kind = 'line'
  AND (SELECT COUNT(*) FROM stg.tac_cash_flow_map AS m WHERE m.sub_code = l.sub_code AND m.treatment = 'derive')
      <> CASE WHEN l.sub_code = 'BAL1240' THEN 0 ELSE 1 END
UNION ALL
SELECT m.sub_code, 'income-statement input that is not a flow'
FROM stg.tac_cash_flow_map AS m
WHERE m.treatment = 'derive' AND m.statement = 'SoCI' AND m.basis <> 'flow'
UNION ALL
-- each flow line goes into its section once (+1) and out of the reserve movement once (-1), nothing else
SELECT m.sub_code, 'income-statement flow without exactly one +1 into a section and one -1 out of the reserve movement'
FROM stg.tac_cash_flow_map AS m
WHERE m.treatment = 'derive' AND m.statement = 'SoCI'
GROUP BY m.sub_code
HAVING SUM(CASE WHEN m.factor = 1 AND m.derived_line <> 'D_NC_RES' THEN 1 ELSE 0 END) <> 1
    OR SUM(CASE WHEN m.factor = -1 AND m.derived_line = 'D_NC_RES' THEN 1 ELSE 0 END) <> 1
    OR COUNT(*) <> 2
UNION ALL
-- a published line is compared with a derived line of its own section ("Operating activities" and so on)
SELECT m.sub_code, 'published line compared with a derived line of another section'
FROM stg.tac_cash_flow_map AS m
JOIN dw.tac_statutory_line AS l ON l.sub_code = m.sub_code
JOIN dw.tac_cash_flow_line AS d ON d.line_code = m.derived_line
WHERE m.treatment = 'compare' AND d.section <> l.section
UNION ALL
SELECT l.sub_code, 'published cash-flow line that is compared with nothing'
FROM dw.tac_statutory_line AS l
WHERE l.statement = 'SoCF' AND l.line_kind = 'line'
  AND l.section IN ('Operating activities', 'Investing activities', 'Financing activities')
  AND NOT EXISTS (SELECT 1 FROM dw.tac_cash_flow_comparison AS c WHERE c.line_key = l.line_key)
UNION ALL
SELECT d.line_code, 'derived line that no row of the map uses'
FROM dw.tac_cash_flow_line AS d
WHERE NOT EXISTS (SELECT 1 FROM stg.tac_cash_flow_map AS m WHERE m.derived_line = d.line_code)
UNION ALL
-- the kind of a derived line says which sides exist
SELECT d.line_code, 'kind says the line has a published side but none is compared, or the reverse'
FROM dw.tac_cash_flow_line AS d
WHERE (d.line_kind IN ('compared', 'published_only')
       AND NOT EXISTS (SELECT 1 FROM stg.tac_cash_flow_map AS m WHERE m.derived_line = d.line_code AND m.treatment = 'compare'))
   OR (d.line_kind = 'derived_only'
       AND EXISTS (SELECT 1 FROM stg.tac_cash_flow_map AS m WHERE m.derived_line = d.line_code AND m.treatment = 'compare'))
   OR (d.line_kind IN ('compared', 'derived_only')
       AND NOT EXISTS (SELECT 1 FROM stg.tac_cash_flow_map AS m WHERE m.derived_line = d.line_code AND m.treatment = 'derive'))
   OR (d.line_kind = 'published_only'
       AND EXISTS (SELECT 1 FROM stg.tac_cash_flow_map AS m WHERE m.derived_line = d.line_code AND m.treatment = 'derive'))
UNION ALL
SELECT section, 'derived line sections are not exactly the three published sections and the reserve movements'
FROM (SELECT DISTINCT section FROM dw.tac_cash_flow_line) AS s
WHERE section NOT IN (N'Operating activities', N'Investing activities', N'Financing activities', N'Reserve movements (not cash)')
UNION ALL
SELECT 'map', 'authored/tac_cash_flow_map.csv has other than 148 rows'
WHERE (SELECT COUNT(*) FROM stg.tac_cash_flow_map) <> 148;
