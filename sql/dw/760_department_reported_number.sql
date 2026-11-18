-- dw.department_reported_number: for every department number that an outturn line was reported under, the
-- department of the current structure that answers for it. The model uses it to read "the same department" in
-- the structure each release reported (the department number of the organisation version the release used) from a
-- row of the current structure, keyed on the number and never on the name.
--
-- Rules, in this order; the first that gives a department decides the number:
--   own number          a live department of type Department carries the number (dw.current_structure_department)
--   unallocated member  no live department carries it, and the Unallocated member 'U' + the number exists
--                       (U011, U035, U077: a department that closed and whose lines no current department took)
--   largest receiver    neither: the live department that the lines reported under the number go to in the
--                       current structure, taking the one with the largest absolute net amount (ties: lowest key).
--                       This happens for one number, 027, the Foreign and Commonwealth Office, whose lines go to the
--                       Foreign, Commonwealth and Development Office.
-- Every number maps to exactly one department, so the amounts of the as-reported structure, added over the
-- departments of the current structure, add back to the total: the machinery of government transfer sums to
-- zero. An Unallocated member whose number a live department already carries (U084) answers for no number: its
-- lines were reported under 084 and the as-reported figure of 084 belongs to the department that carries it.
--
-- dw.v_model_department is the model's view of the current-structure departments (the rows of dw.dim_department
-- that dw.current_structure_department marks is_live; a closed naming period never receives a line), with the
-- numbers a department answers for written as |030|027|, so that a measure can read the set by text.

DROP VIEW IF EXISTS dw.v_model_department;
GO
DROP TABLE IF EXISTS dw.department_reported_number;
GO

CREATE TABLE dw.department_reported_number (
    reported_department_number nvarchar(10)  NOT NULL CONSTRAINT pk_dw_department_reported_number PRIMARY KEY,
    current_department_key     int           NOT NULL,
    mapping_rule               varchar(30)   NOT NULL,
    reported_lines             bigint        NOT NULL,   -- fact rows reported under the number
    reported_net_amount        decimal(19,4) NOT NULL    -- their net amount, GBP thousands
);
GO

WITH reported AS (
    -- the department number each fact row was reported under: the department of the organisation version the release used
    SELECT d.department_number, f.current_department_key, COUNT_BIG(*) AS n, SUM(f.amount_delta) AS amount
    FROM dw.fact_outturn AS f
    JOIN dw.dim_organisation AS o ON o.organisation_key = f.organisation_key
    JOIN dw.dim_department AS d ON d.department_key = o.department_key
    GROUP BY d.department_number, f.current_department_key
), numbers AS (
    SELECT department_number, SUM(n) AS n, SUM(amount) AS amount FROM reported GROUP BY department_number
), receiver AS (
    SELECT department_number, current_department_key,
           ROW_NUMBER() OVER (PARTITION BY department_number ORDER BY ABS(amount) DESC, current_department_key) AS rn
    FROM reported
)
INSERT INTO dw.department_reported_number
    (reported_department_number, current_department_key, mapping_rule, reported_lines, reported_net_amount)
SELECT n.department_number,
       COALESCE(own.department_key, una.department_key, r.current_department_key),
       CAST(CASE WHEN own.department_key IS NOT NULL THEN 'own number'
                 WHEN una.department_key IS NOT NULL THEN 'unallocated member'
                 ELSE 'largest receiver' END AS varchar(30)),
       n.n, CAST(n.amount AS decimal(19, 4))
FROM numbers AS n
LEFT JOIN (SELECT d.department_key, d.department_number
           FROM dw.dim_department AS d
           JOIN dw.current_structure_department AS c ON c.department_key = d.department_key
           WHERE c.is_live = 1 AND d.member_type = 'Department') AS own ON own.department_number = n.department_number
LEFT JOIN (SELECT d.department_key, d.department_number
           FROM dw.dim_department AS d
           JOIN dw.current_structure_department AS c ON c.department_key = d.department_key
           WHERE c.is_live = 1 AND d.member_type = 'Unallocated') AS una ON una.department_number = N'U' + n.department_number
JOIN receiver AS r ON r.department_number = n.department_number AND r.rn = 1;
GO

CREATE VIEW dw.v_model_department
AS
SELECT d.department_key, d.department_number, d.department_name, d.member_type, d.valid_from_release,
       d.valid_to_release,
       ISNULL(N'|' + (SELECT STRING_AGG(CAST(m.reported_department_number AS nvarchar(max)), N'|')
                              WITHIN GROUP (ORDER BY m.reported_department_number)
                      FROM dw.department_reported_number AS m
                      WHERE m.current_department_key = d.department_key) + N'|', N'') AS reported_department_numbers
FROM dw.dim_department AS d
JOIN dw.current_structure_department AS c ON c.department_key = d.department_key
WHERE c.is_live = 1;
GO
