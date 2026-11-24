-- test: every organisation-month cell of dw.workforce_month that has a payroll full-time equivalent or paybill has exactly one row in dw.v_pay_cell, every row has a department of the current structure that exists in dw.v_model_department, and the cells split into the pinned counts by status (6,248 valid, 237 with no full-time equivalent or zero, 110 with no paybill or paybill of zero or less, 28 on a published row whose total is not its components); a different count means the load or the rule changed
-- marker: localdata
-- requires: dw.workforce_month, audit.workforce_row_arithmetic
SELECT 'cells' AS what, 'cells of dw.workforce_month and rows of dw.v_pay_cell differ' AS problem
FROM (SELECT COUNT(*) AS n FROM (SELECT DISTINCT durable_key, month_start FROM dw.workforce_month
                                 WHERE measure_key IN ('payroll_fte', 'payroll_paybill_gbp')) AS x) AS a
CROSS JOIN (SELECT COUNT(*) AS n, COUNT(DISTINCT CONCAT(durable_key, '|', month_start)) AS d FROM dw.v_pay_cell) AS b
WHERE a.n <> b.n OR b.n <> b.d
UNION ALL
SELECT CONCAT('department ', c.department_key), 'department of a cell is not a department of the current structure'
FROM dw.v_pay_cell AS c
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_department AS d WHERE d.department_key = c.department_key)
GROUP BY c.department_key
UNION ALL
SELECT e.cell_status, CONCAT('expected ', e.expected_cells, ' cells, found ', COALESCE(a.n, 0))
FROM (VALUES ('valid', 6248), ('fte_blank_or_zero', 237), ('paybill_blank_or_zero', 110), ('row_arithmetic', 28)) AS e (cell_status, expected_cells)
LEFT JOIN (SELECT cell_status, COUNT(*) AS n FROM dw.v_pay_cell GROUP BY cell_status) AS a ON a.cell_status = e.cell_status
WHERE COALESCE(a.n, 0) <> e.expected_cells
UNION ALL
SELECT cell_status, 'a status that is not one of the four'
FROM dw.v_pay_cell WHERE cell_status NOT IN ('valid', 'fte_blank_or_zero', 'paybill_blank_or_zero', 'row_arithmetic')
GROUP BY cell_status;
