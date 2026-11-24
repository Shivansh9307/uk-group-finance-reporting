-- test: the department a pay cell is placed in is the department of the organisation version in force in the month, found here by a different rule from the view (the latest valid-from release on or before the month, or the earliest release when the month is before every version) and not by the view's ordering; every cell has one such department
-- marker: localdata
-- requires: dw.v_pay_cell, dw.dim_organisation, dw.dim_department, dw.department_reported_number
WITH inforce AS (
    SELECT c.durable_key, c.month_start,
           COALESCE((SELECT MAX(o.valid_from_release) FROM dw.dim_organisation AS o
                     WHERE o.durable_key = c.durable_key AND o.valid_from_release <= c.report_month),
                    (SELECT MIN(o.valid_from_release) FROM dw.dim_organisation AS o
                     WHERE o.durable_key = c.durable_key)) AS rel
    FROM dw.v_pay_cell AS c
)
SELECT CONCAT(c.durable_key, ' ', c.month_start) AS what, 'department is not that of the version in force' AS problem
FROM dw.v_pay_cell AS c
JOIN inforce AS i ON i.durable_key = c.durable_key AND i.month_start = c.month_start
WHERE NOT EXISTS (SELECT 1
                  FROM dw.dim_organisation AS o
                  JOIN dw.dim_department AS d ON d.department_key = o.department_key
                  JOIN dw.department_reported_number AS r ON r.reported_department_number = d.department_number
                  WHERE o.durable_key = c.durable_key AND o.valid_from_release = i.rel
                    AND r.current_department_key = c.department_key);
