-- scope: full
-- dw.forecast_return_quality: the returns (or one organisation or department group inside a return) that are known to be bad,
-- one row per flag. Found by rules over the data, never by a hard-coded key; nothing is dropped from dw.forecast_return, the
-- flag is how a report or a measure leaves the row out. The final outturn R13 of the year is the yardstick, so R13 itself is
-- never flagged.
-- Measure: gross = the sum of |amount| over periods 1 to 12 of the rows with budget measure RDEL, CDEL or AME (so that income and
-- spending do not net away). floor = GBP 1bn = 1,000,000 in thousands. ratio = gross in the return / gross in R13.
--   rule 'u'  units error, organisation: the organisation's gross in the return is 500 to 2,000 times its R13 gross (R13 > 0)
--             and at least the floor: a figure keyed in pounds instead of thousands
--   rule 's'  scale outlier, organisation: the ratio is 20 or more and the rule is not 'u', gross at least the floor
--   rule 'x'  organisation not in the final: gross at least the floor in the return and no R13 gross at all
--   rule 'm'  department group missing: its R13 gross is at least the floor and it has no row at all in the return
--   rule 'p'  department group nearly missing: its R13 gross is at least the floor and its gross in the return is under
--             10% of it, but not zero
--   level      organisation | department group; organisation_code is '' at department-group level
--   amount_affected  GBP thousands, positive: the excess over R13 (u, s, x) or the shortfall against R13 (m, p)
-- A department group is the department as the return reports it. dw.forecast_accuracy sets is_flagged_return where its
-- department group, financial year and return are in this table.

DROP TABLE IF EXISTS dw.forecast_return_quality;
GO

CREATE TABLE dw.forecast_return_quality (
    financial_year         varchar(7)     NOT NULL,
    return_no              tinyint        NOT NULL,
    rule_code              char(1)        NOT NULL,
    department_group_code  nvarchar(50)   NOT NULL,
    organisation_code      nvarchar(50)   NOT NULL,   -- '' at department-group level
    rule_name              varchar(40)    NOT NULL,
    level                  varchar(16)    NOT NULL,
    return_gross           decimal(19,4)  NOT NULL,
    final_gross            decimal(19,4)  NOT NULL,
    ratio                  decimal(19,4)  NULL,
    amount_affected        decimal(19,4)  NOT NULL,
    evidence               nvarchar(400)  NOT NULL,
    CONSTRAINT pk_dw_forecast_return_quality PRIMARY KEY (financial_year, return_no, rule_code, department_group_code, organisation_code),
    CONSTRAINT ck_dw_forecast_return_quality_rule CHECK (rule_code IN ('u', 's', 'x', 'm', 'p'))
);
GO

WITH org_gross AS (
    SELECT r.financial_year, r.return_no, r.organisation_code, MIN(r.department_group_code) AS department_group_code,
           SUM(ABS(r.amount)) AS gross
    FROM dw.forecast_return AS r
    WHERE r.period BETWEEN 1 AND 12 AND r.budget_measure IN ('RDEL', 'CDEL', 'AME')
    GROUP BY r.financial_year, r.return_no, r.organisation_code
),
grp_gross AS (
    SELECT r.financial_year, r.return_no, r.department_group_code, SUM(ABS(r.amount)) AS gross
    FROM dw.forecast_return AS r
    WHERE r.period BETWEEN 1 AND 12 AND r.budget_measure IN ('RDEL', 'CDEL', 'AME')
    GROUP BY r.financial_year, r.return_no, r.department_group_code
),
org_flag AS (
    SELECT o.financial_year, o.return_no, o.department_group_code, o.organisation_code, o.gross AS return_gross,
           COALESCE(f.gross, 0) AS final_gross,
           CASE WHEN COALESCE(f.gross, 0) = 0 THEN NULL ELSE CAST(o.gross / f.gross AS decimal(19, 4)) END AS ratio
    FROM org_gross AS o
    LEFT JOIN org_gross AS f ON f.financial_year = o.financial_year AND f.return_no = 13 AND f.organisation_code = o.organisation_code
    WHERE o.return_no <= 12 AND o.gross >= 1000000
),
grp_flag AS (
    SELECT h.financial_year, h.return_no, f.department_group_code, COALESCE(g.gross, 0) AS return_gross, f.gross AS final_gross
    FROM grp_gross AS f
    JOIN dw.forecast_return_header AS h ON h.financial_year = f.financial_year AND h.return_no <= 12
    LEFT JOIN grp_gross AS g ON g.financial_year = f.financial_year AND g.return_no = h.return_no
                            AND g.department_group_code = f.department_group_code
    WHERE f.return_no = 13 AND f.gross >= 1000000
)
INSERT INTO dw.forecast_return_quality
    (financial_year, return_no, rule_code, department_group_code, organisation_code, rule_name, level, return_gross, final_gross,
     ratio, amount_affected, evidence)
SELECT q.financial_year, q.return_no, q.rule_code, q.department_group_code, q.organisation_code, q.rule_name, q.level,
       q.return_gross, q.final_gross, q.ratio, q.amount_affected, q.evidence
FROM (
    SELECT financial_year, return_no, CAST('u' AS char(1)) AS rule_code, department_group_code, organisation_code,
           CAST('units error' AS varchar(40)) AS rule_name, CAST('organisation' AS varchar(16)) AS level,
           return_gross, final_gross, ratio, return_gross - final_gross AS amount_affected,
           CAST(N'Gross of ' + organisation_code + N' in R' + CAST(return_no AS nvarchar(3)) + N' is ' + CAST(ratio AS nvarchar(30))
                + N' times its R13: a figure keyed in pounds instead of thousands.' AS nvarchar(400)) AS evidence
    FROM org_flag WHERE ratio BETWEEN 500 AND 2000
    UNION ALL
    SELECT financial_year, return_no, 's', department_group_code, organisation_code, 'scale outlier', 'organisation',
           return_gross, final_gross, ratio, return_gross - final_gross,
           N'Gross of ' + organisation_code + N' in R' + CAST(return_no AS nvarchar(3)) + N' is ' + CAST(ratio AS nvarchar(30))
           + N' times its R13.'
    FROM org_flag WHERE ratio >= 20 AND ratio NOT BETWEEN 500 AND 2000
    UNION ALL
    SELECT financial_year, return_no, 'x', department_group_code, organisation_code, 'organisation not in the final', 'organisation',
           return_gross, final_gross, NULL, return_gross,
           N'Gross of ' + organisation_code + N' in R' + CAST(return_no AS nvarchar(3)) + N' has nothing against it in R13.'
    FROM org_flag WHERE final_gross = 0
    UNION ALL
    SELECT financial_year, return_no, 'm', department_group_code, N'', 'department group missing', 'department group',
           return_gross, final_gross, NULL, final_gross - return_gross,
           N'R' + CAST(return_no AS nvarchar(3)) + N' has no row for ' + department_group_code + N', which has a gross of the amount shown in R13.'
    FROM grp_flag WHERE return_gross = 0
    UNION ALL
    SELECT financial_year, return_no, 'p', department_group_code, N'', 'department group nearly missing', 'department group',
           return_gross, final_gross, CAST(return_gross / final_gross AS decimal(19, 4)), final_gross - return_gross,
           N'R' + CAST(return_no AS nvarchar(3)) + N' holds under a tenth of the R13 gross of ' + department_group_code + N'.'
    FROM grp_flag WHERE return_gross > 0 AND return_gross < 0.1 * final_gross
) AS q;
GO
