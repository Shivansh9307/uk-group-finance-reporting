-- scope: full
-- The pay line of the forecast returns and what the FTE x cost method needs: the department of the current structure
-- that each department group answers to, the pay line as each return states it, the prior year's pay profile, and for every
-- group, year and return the workforce input of the FTE x cost method (or the reason there is none).
-- The files sit in sql/audit/ because they read dw.v_pay_cell (sql/audit/900), which reads audit.workforce_row_arithmetic.
-- Real data only: the forecast returns, and the paybill and full-time equivalent of the workforce files that the pay bridge
-- already accepts (cell_status = 'valid'). Nothing is authored or synthetic.
--
-- The pay line is economic category A101 (the statement's line R30 Pay) of the control budget RDEL, as the returns report it:
-- the department group's pay of its core department and of its arm's length bodies that report to it. Departmental AME has a
-- little A101 too; it is not part of the line.
--
--   dw.forecast_group_department   department group -> department of the current structure, by the department number in the
--                                  group's code, through dw.department_reported_number (the rule the outturn uses); -1 where
--                                  the number maps to nothing
--   dw.forecast_pay_input          the pay line of return n, months 1 to n, as return n states them (the information set of the
--                                  methods; the same shape as dw.forecast_own_input)
--   dw.forecast_pay_prior_profile  the pay line of R13 of the prior year (the same shape as dw.forecast_prior_profile)
--   dw.forecast_fte_cost_input     for a group, year and return n where the method applies: the workforce of the month the
--                                  return has just closed (month n), summed over the valid organisation-month cells of the
--                                  department, in pounds, and the pay line of that month in the return, in GBP thousands
--   audit.forecast_fte_cost_coverage  every group, year and return 1 to 11 with a pay line, and either 'covered' or why not

DROP TABLE IF EXISTS audit.forecast_fte_cost_coverage;
GO
DROP TABLE IF EXISTS dw.forecast_fte_cost_input;
GO
DROP TABLE IF EXISTS dw.forecast_pay_prior_profile;
GO
DROP TABLE IF EXISTS dw.forecast_pay_input;
GO
DROP TABLE IF EXISTS dw.forecast_group_department;
GO

CREATE TABLE dw.forecast_group_department (
    department_group_code      nvarchar(50)  NOT NULL CONSTRAINT pk_dw_forecast_group_department PRIMARY KEY,
    reported_department_number nvarchar(10)  NOT NULL,
    department_key             int           NOT NULL,   -- department of the current structure; -1 where there is none
    mapping_rule               varchar(30)   NOT NULL
);
GO

INSERT INTO dw.forecast_group_department (department_group_code, reported_department_number, department_key, mapping_rule)
SELECT g.department_group_code, SUBSTRING(g.department_group_code, 4, 3),
       COALESCE(r.current_department_key, -1), COALESCE(r.mapping_rule, 'no department number')
FROM (SELECT DISTINCT department_group_code FROM dw.forecast_return) AS g
LEFT JOIN dw.department_reported_number AS r ON r.reported_department_number = SUBSTRING(g.department_group_code, 4, 3);
GO

CREATE TABLE dw.forecast_pay_input (
    financial_year         varchar(7)     NOT NULL,
    return_no              tinyint        NOT NULL,
    department_group_code  nvarchar(50)   NOT NULL,
    budget_measure         varchar(5)     NOT NULL,   -- always RDEL: the pay line is resource DEL
    period                 tinyint        NOT NULL,
    amount                 decimal(19,4)  NOT NULL,
    source_rows            int            NOT NULL,
    CONSTRAINT pk_dw_forecast_pay_input PRIMARY KEY (financial_year, return_no, department_group_code, budget_measure, period),
    CONSTRAINT ck_dw_forecast_pay_input_known CHECK (period BETWEEN 1 AND return_no)
);
GO

INSERT INTO dw.forecast_pay_input (financial_year, return_no, department_group_code, budget_measure, period, amount, source_rows)
SELECT r.financial_year, r.return_no, r.department_group_code, 'RDEL', r.period, SUM(r.amount), SUM(r.source_rows)
FROM dw.forecast_return AS r
WHERE r.return_no BETWEEN 1 AND 12 AND r.is_actual = 1 AND r.budget_measure = 'RDEL' AND r.economic_category_code = 'A101'
GROUP BY r.financial_year, r.return_no, r.department_group_code, r.period;
GO

CREATE TABLE dw.forecast_pay_prior_profile (
    financial_year          varchar(7)     NOT NULL,
    profile_financial_year  varchar(7)     NOT NULL,
    department_group_code   nvarchar(50)   NOT NULL,
    budget_measure          varchar(5)     NOT NULL,
    period                  tinyint        NOT NULL,
    amount                  decimal(19,4)  NOT NULL,
    CONSTRAINT pk_dw_forecast_pay_prior_profile PRIMARY KEY (financial_year, department_group_code, budget_measure, period)
);
GO

INSERT INTO dw.forecast_pay_prior_profile (financial_year, profile_financial_year, department_group_code, budget_measure, period, amount)
SELECT cur.financial_year, prev.financial_year, r.department_group_code, 'RDEL', r.period, SUM(r.amount)
FROM dw.forecast_return_header AS prev
JOIN dw.forecast_return_header AS cur ON cur.year_seq = prev.year_seq + 1 AND cur.return_no = 13
JOIN dw.forecast_return AS r ON r.financial_year = prev.financial_year AND r.return_no = 13
WHERE prev.return_no = 13 AND r.period BETWEEN 1 AND 12 AND r.budget_measure = 'RDEL' AND r.economic_category_code = 'A101'
GROUP BY cur.financial_year, prev.financial_year, r.department_group_code, r.period;
GO

-- the workforce of one department and month: the valid cells of the pay bridge, summed. A cell is an organisation and a month.
CREATE TABLE audit.forecast_fte_cost_coverage (
    financial_year         varchar(7)     NOT NULL,
    return_no              tinyint        NOT NULL,
    department_group_code  nvarchar(50)   NOT NULL,
    department_key         int            NOT NULL,
    status                 varchar(30)    NOT NULL,   -- covered | no_workforce_cell_in_month | shared_department | no_department
    month_start            date           NOT NULL,   -- the calendar month of the return's last actual month (period = return_no)
    workforce_fte          decimal(19,4)  NULL,
    workforce_paybill_gbp  decimal(19,4)  NULL,       -- pounds
    workforce_cells        int            NULL,       -- organisation-month cells added
    pay_month_n            decimal(19,4)  NULL,       -- the pay line of that month in the return, GBP thousands
    pay_cover_share        decimal(19,10) NULL,       -- workforce paybill of the month as a share of the return's pay line of the month
    CONSTRAINT pk_audit_forecast_fte_cost_coverage PRIMARY KEY (financial_year, return_no, department_group_code)
);
GO

WITH w AS (
    SELECT c.department_key, c.month_start, SUM(c.fte) AS fte, SUM(c.paybill) AS paybill, COUNT(*) AS cells
    FROM dw.v_pay_cell AS c
    WHERE c.cell_status = 'valid'
    GROUP BY c.department_key, c.month_start
),
groups_in_year AS (   -- how many department groups with a pay line answer to one department in one year
    SELECT p.financial_year, g.department_key, COUNT(DISTINCT p.department_group_code) AS groups_n
    FROM dw.forecast_pay_input AS p
    JOIN dw.forecast_group_department AS g ON g.department_group_code = p.department_group_code
    GROUP BY p.financial_year, g.department_key
),
pr AS (   -- the return's own pay line in the month it has just closed
    SELECT financial_year, return_no, department_group_code, amount AS pay_month_n
    FROM dw.forecast_pay_input WHERE period = return_no
),
k AS (
    SELECT DISTINCT p.financial_year, p.return_no, p.department_group_code
    FROM dw.forecast_pay_input AS p WHERE p.return_no BETWEEN 1 AND 11
),
j AS (
    SELECT k.financial_year, k.return_no, k.department_group_code, g.department_key,
           DATEADD(MONTH, k.return_no - 1, DATEFROMPARTS(CAST(LEFT(k.financial_year, 4) AS int), 4, 1)) AS month_start,
           y.groups_n, w.fte, w.paybill, w.cells, pr.pay_month_n
    FROM k
    JOIN dw.forecast_group_department AS g ON g.department_group_code = k.department_group_code
    JOIN groups_in_year AS y ON y.financial_year = k.financial_year AND y.department_key = g.department_key
    LEFT JOIN pr ON pr.financial_year = k.financial_year AND pr.return_no = k.return_no AND pr.department_group_code = k.department_group_code
    LEFT JOIN w ON w.department_key = g.department_key
               AND w.month_start = DATEADD(MONTH, k.return_no - 1, DATEFROMPARTS(CAST(LEFT(k.financial_year, 4) AS int), 4, 1))
)
INSERT INTO audit.forecast_fte_cost_coverage
    (financial_year, return_no, department_group_code, department_key, status, month_start, workforce_fte, workforce_paybill_gbp,
     workforce_cells, pay_month_n, pay_cover_share)
SELECT j.financial_year, j.return_no, j.department_group_code, j.department_key,
       CAST(CASE WHEN j.department_key = -1 THEN 'no_department'
                 WHEN j.groups_n > 1 THEN 'shared_department'
                 WHEN j.fte IS NULL THEN 'no_workforce_cell_in_month'
                 ELSE 'covered' END AS varchar(30)),
       j.month_start,
       CASE WHEN j.department_key <> -1 AND j.groups_n = 1 THEN j.fte END,
       CASE WHEN j.department_key <> -1 AND j.groups_n = 1 THEN j.paybill END,
       CASE WHEN j.department_key <> -1 AND j.groups_n = 1 THEN j.cells END,
       j.pay_month_n,
       CASE WHEN j.department_key <> -1 AND j.groups_n = 1 AND j.fte IS NOT NULL AND j.pay_month_n > 0
            THEN CAST(j.paybill AS decimal(30, 10)) / (CAST(j.pay_month_n AS decimal(30, 10)) * 1000) END
FROM j;
GO

CREATE TABLE dw.forecast_fte_cost_input (
    financial_year         varchar(7)     NOT NULL,
    return_no              tinyint        NOT NULL,
    department_group_code  nvarchar(50)   NOT NULL,
    department_key         int            NOT NULL,
    month_start            date           NOT NULL,
    workforce_fte          decimal(19,4)  NOT NULL,
    workforce_paybill_gbp  decimal(19,4)  NOT NULL,
    workforce_cells        int            NOT NULL,
    pay_month_n            decimal(19,4)  NULL,
    CONSTRAINT pk_dw_forecast_fte_cost_input PRIMARY KEY (financial_year, return_no, department_group_code)
);
GO

INSERT INTO dw.forecast_fte_cost_input
    (financial_year, return_no, department_group_code, department_key, month_start, workforce_fte, workforce_paybill_gbp, workforce_cells, pay_month_n)
SELECT financial_year, return_no, department_group_code, department_key, month_start, workforce_fte, workforce_paybill_gbp, workforce_cells, pay_month_n
FROM audit.forecast_fte_cost_coverage WHERE status = 'covered';
GO
