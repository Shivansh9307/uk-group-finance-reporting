-- audit.current_structure_coverage: how the current-structure map treats the lines, per financial year.
--   One row per financial year that has a year-end release (the June release that holds periods 1 to 12),
--   rule (method), former department (the department of the durable key's latest version) and current
--   department. Amounts come from stg.inyear_snapshot in that year-end release, GBP thousands:
--     net_amount    the sum of the rows, spending positive
--     gross_amount  the sum, over the lines, of the absolute value of each line's total for the year (the size
--                   of the lines, not what is left after income offsets spending; the profile's "gross")
--   lines = (organisation version, sub-segment) pairs with rows in that release; rows_n = snapshot rows.
--   A line of an Unallocated member is whole: it carries its own amount, never a share of another's.

DROP TABLE IF EXISTS audit.current_structure_coverage;
GO

CREATE TABLE audit.current_structure_coverage (
    financial_year              varchar(7)    NOT NULL,
    method                      varchar(40)   NOT NULL,
    former_department_key       int           NOT NULL,
    former_department_number    nvarchar(10)  NOT NULL,
    former_department_name      nvarchar(400) NOT NULL,
    current_department_key      int           NOT NULL,
    current_department_number   nvarchar(10)  NOT NULL,
    current_department_name     nvarchar(400) NOT NULL,
    current_member_type         varchar(20)   NOT NULL,
    lines                       int           NOT NULL,
    rows_n                      int           NOT NULL,
    net_amount                  decimal(19,4) NOT NULL,
    gross_amount                decimal(19,4) NOT NULL,
    CONSTRAINT pk_audit_current_structure_coverage
        PRIMARY KEY (financial_year, method, former_department_key, current_department_key)
);
GO

WITH ye AS (
    SELECT release, financial_year FROM stg.release WHERE highest_period = 12
), amt AS (
    SELECT ye.financial_year, m.organisation_key, s.sub_segment_code,
           COUNT(*) AS rows_n, SUM(s.amount) AS net_amount
    FROM ye
    JOIN stg.inyear_snapshot AS s ON s.release = ye.release AND s.financial_year = ye.financial_year
    JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
    GROUP BY ye.financial_year, m.organisation_key, s.sub_segment_code
)
INSERT INTO audit.current_structure_coverage
SELECT a.financial_year, l.method, fd.department_key, fd.department_number, fd.department_name, cd.department_key,
       cd.department_number, cd.department_name, cd.member_type, COUNT(*), SUM(a.rows_n), CAST(SUM(a.net_amount) AS decimal(19,4)), CAST(SUM(ABS(a.net_amount)) AS decimal(19,4))
FROM amt AS a
JOIN dw.current_structure_line AS l ON l.organisation_key = a.organisation_key AND l.sub_segment_code = a.sub_segment_code
JOIN dw.dim_department AS fd ON fd.department_key = l.former_department_key
JOIN dw.dim_department AS cd ON cd.department_key = l.current_department_key
GROUP BY a.financial_year, l.method, fd.department_key, fd.department_number, fd.department_name, cd.department_key,
         cd.department_number, cd.department_name, cd.member_type;
GO
