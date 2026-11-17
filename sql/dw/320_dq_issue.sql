-- dw.dq_issue: one row per data-quality finding in the in-year data. Every finding is found by a rule
-- over the data, never by a hard-coded key.
--   rule 'a'  unit error: a line whose absolute amount is over GBP 1bn (1,000,000 in thousands) in one of two
--             consecutive releases of one year, with the same sign, changing by a factor between 900 and 1,100
--             from one release to the next. One finding per line and release pair. Two fact rows carry the
--             finding's id in dw.fact_outturn.dq_issue_id: the line's delta row in the second release (the
--             correction) and its latest delta row at or before the first release (the row that set the amount). The sign test
--             keeps out a line that really changes from a small to a large amount (the HMRC subsidy line
--             X041A094 goes from -1,811 to 1,890,000 between December 2021 and March 2022: a different
--             sign and a factor of 1,043).
--             The rule cannot see an error that is not corrected in the next release, or one on a line that
--             first appears already wrong.
--   rule 'b'  a release whose Quarter column disagrees with its Month column (September 2022 labels all of
--             its rows 'Qtr1 - 21-22' for April to June 2022). Read from raw. Informational: the warehouse
--             derives the quarter from the month and never reads the column.
--   rule 'c'  period 0 rows ("not allocated to a month"): the 71 rows of June 2019. Informational: they are
--             kept, in the year total and in year to date.
--   rule 'd'  a code that is a second spelling of another code in the same release, from the rows of
--             authored/organisation_key_override.csv with reason 'coding_error' (EHR030 in June 2019).
--             Informational: the warehouse maps the code to the other code's version.
-- Only rule 'a' touches the fact; the rest do not flag fact rows. The ids are 1.. in (rule, first release,
-- organisation code, sub-segment, category, period) order, so a rebuild gives the same ids.

DROP TABLE IF EXISTS dw.dq_issue;
GO

CREATE TABLE dw.dq_issue (
    dq_issue_id                 int            NOT NULL CONSTRAINT pk_dw_dq_issue PRIMARY KEY,
    issue_rule                  char(1)        NOT NULL,
    issue_type                  varchar(40)    NOT NULL,
    flags_fact_rows             bit            NOT NULL,
    description                 nvarchar(1000) NOT NULL,
    treatment                   nvarchar(500)  NOT NULL,
    release_from                varchar(7)     NOT NULL,
    release_to                  varchar(7)     NOT NULL,
    organisation_key            int            NULL,
    organisation_code           nvarchar(50)   NULL,
    segment_key                 int            NULL,
    sub_segment_code            nvarchar(50)   NULL,
    account_key                 int            NULL,
    economic_category_code      nvarchar(50)   NULL,
    control_budget_key          int            NULL,
    control_budget_detail_code  nvarchar(100)  NULL,
    period_key                  int            NULL,
    amount_before               decimal(19,4)  NULL,
    amount_after                decimal(19,4)  NULL,
    rows_affected               int            NOT NULL
);
GO

INSERT INTO dw.dq_issue
    (dq_issue_id, issue_rule, issue_type, flags_fact_rows, description, treatment, release_from, release_to,
     organisation_key, organisation_code, segment_key, sub_segment_code, account_key, economic_category_code,
     control_budget_key, control_budget_detail_code, period_key, amount_before, amount_after, rows_affected)
SELECT ROW_NUMBER() OVER (ORDER BY f.issue_rule, f.release_from, f.release_to, f.organisation_code,
                                   f.sub_segment_code, f.economic_category_code, f.control_budget_detail_code, f.period_key),
       f.issue_rule, f.issue_type, f.flags_fact_rows, f.description, f.treatment, f.release_from, f.release_to,
       f.organisation_key, f.organisation_code, f.segment_key, f.sub_segment_code, f.account_key, f.economic_category_code,
       f.control_budget_key, f.control_budget_detail_code, f.period_key, f.amount_before, f.amount_after, f.rows_affected
FROM (
    -- rule a: unit errors, on the line snapshot
    SELECT CAST('a' AS char(1)) AS issue_rule, CAST('unit error' AS varchar(40)) AS issue_type, CAST(1 AS bit) AS flags_fact_rows,
           CAST(N'The amount changes by a factor of about 1,000 with the same sign from release ' + ra.label + N' to release '
                + rb.label + N' (' + FORMAT(a.amount, 'N0') + N' then ' + FORMAT(b.amount, 'N0')
                + N', GBP thousands). It looks like a unit error that the next release corrects, or the correction of one.' AS nvarchar(1000)) AS description,
           CAST(N'Exclude the line from gross restatement measures, or annotate it.' AS nvarchar(500)) AS treatment,
           ra.label AS release_from, rb.label AS release_to,
           a.organisation_key, o.organisation_code, a.segment_key, sg.sub_segment_code, a.account_key, ac.economic_category_code,
           a.control_budget_key, cb.control_budget_detail_code, a.period_key,
           a.amount AS amount_before, b.amount AS amount_after, CAST(2 AS int) AS rows_affected
    FROM stg.outturn_line_snapshot AS a
    JOIN dw.dim_release AS ra ON ra.release_seq = a.release_seq
    JOIN dw.dim_release AS rb ON rb.release_seq = a.release_seq + 1 AND rb.financial_year = ra.financial_year
    JOIN stg.outturn_line_snapshot AS b
      ON b.release_seq = rb.release_seq AND b.organisation_key = a.organisation_key AND b.segment_key = a.segment_key
     AND b.account_key = a.account_key AND b.control_budget_key = a.control_budget_key AND b.period_key = a.period_key
    JOIN dw.dim_organisation AS o ON o.organisation_key = a.organisation_key
    JOIN dw.dim_segment AS sg ON sg.segment_key = a.segment_key
    JOIN dw.dim_account AS ac ON ac.account_key = a.account_key
    JOIN dw.dim_control_budget AS cb ON cb.control_budget_key = a.control_budget_key
    WHERE (ABS(a.amount) > 1000000 OR ABS(b.amount) > 1000000)
      AND SIGN(a.amount) = SIGN(b.amount)
      AND (ABS(a.amount) BETWEEN 900 * ABS(b.amount) AND 1100 * ABS(b.amount)
        OR ABS(b.amount) BETWEEN 900 * ABS(a.amount) AND 1100 * ABS(a.amount))

    UNION ALL
    -- rule b: the Quarter column disagrees with the Month column, read from raw
    SELECT 'b', 'quarter label wrong', 0,
           CAST(N'The Quarter column disagrees with the month on ' + CAST(q.bad_rows AS nvarchar(20)) + N' of ' + CAST(q.rows_checked AS nvarchar(20))
                + N' rows (for example ' + q.example_label + N' where the month gives ' + q.example_expected + N').' AS nvarchar(1000)),
           N'None needed: the warehouse derives the quarter from the month and never reads the Quarter column.',
           q.release, q.release, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, q.bad_rows
    FROM (
        SELECT c.release, COUNT(*) AS rows_checked, SUM(CASE WHEN c.[quarter] <> c.expected THEN 1 ELSE 0 END) AS bad_rows,
               MAX(CASE WHEN c.[quarter] <> c.expected THEN c.[quarter] END) AS example_label,
               MAX(CASE WHEN c.[quarter] <> c.expected THEN c.expected END) AS example_expected
        FROM (
            SELECT r.release, r.[quarter],
                   N'Qtr' + CAST(((CASE WHEN m.cal_month >= 4 THEN m.cal_month - 3 ELSE m.cal_month + 9 END) + 2) / 3 AS nvarchar(1)) + N' - '
                   + RIGHT(CAST(m.fy_start AS nvarchar(4)), 2) + N'-' + RIGHT(CAST(m.fy_start + 1 AS nvarchar(4)), 2) AS expected
            FROM raw.oscar_inyear AS r
            CROSS APPLY (
                SELECT CASE LEFT(r.[month], 3)
                            WHEN 'Jan' THEN 1 WHEN 'Feb' THEN 2 WHEN 'Mar' THEN 3 WHEN 'Apr' THEN 4 WHEN 'May' THEN 5 WHEN 'Jun' THEN 6
                            WHEN 'Jul' THEN 7 WHEN 'Aug' THEN 8 WHEN 'Sep' THEN 9 WHEN 'Oct' THEN 10 WHEN 'Nov' THEN 11 WHEN 'Dec' THEN 12 END AS cal_month
            ) AS mm
            CROSS APPLY (
                SELECT mm.cal_month,
                       2000 + CAST(RIGHT(r.[month], 2) AS int) - CASE WHEN mm.cal_month >= 4 THEN 0 ELSE 1 END AS fy_start
            ) AS m
            WHERE r.[month] LIKE '[A-Za-z][A-Za-z][A-Za-z]-[0-9][0-9]'
        ) AS c
        GROUP BY c.release
        HAVING SUM(CASE WHEN c.[quarter] <> c.expected THEN 1 ELSE 0 END) > 0
    ) AS q

    UNION ALL
    -- rule c: period 0 rows, "not allocated to a month"
    SELECT 'c', 'period 0 rows', 0,
           CAST(N'The release carries ' + CAST(COUNT(*) AS nvarchar(20)) + N' non-zero rows labelled "Period 0" for financial year ' + MIN(s.financial_year)
                + N', not allocated to a month, GBP ' + FORMAT(SUM(s.amount), 'N0') + N' thousand net.' AS nvarchar(1000)),
           N'Kept as period 0 of the financial year: counted in year totals and year to date, never dropped.',
           s.release, s.release, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, SUM(s.amount), NULL, CAST(COUNT(*) AS int)
    FROM stg.inyear_snapshot AS s
    WHERE s.period = 0
    GROUP BY s.release

    UNION ALL
    -- rule d: a second spelling of another code in the same release, from the authored overrides
    SELECT 'd', 'coding error', 0,
           CAST(N'Code ' + k.organisation_code + N' is reported in the same release as ' + k.merge_into_code
                + N' and is a second spelling of it (' + CAST(k.rows_in_snapshot AS nvarchar(20)) + N' non-zero rows).' AS nvarchar(1000)),
           N'The warehouse maps the code to the version of ' + k.merge_into_code + N'; its rows keep the department the release reports for it.',
           fr.label, tr.label, NULL, k.organisation_code, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, k.rows_in_snapshot
    FROM (
        SELECT o.organisation_code, o.merge_into_code, o.valid_from_seq, o.valid_to_seq,
               (SELECT COUNT(*) FROM stg.inyear_snapshot AS s
                JOIN stg.release AS r ON r.release = s.release
                WHERE s.organisation_code = o.organisation_code AND r.release_seq BETWEEN o.valid_from_seq AND o.valid_to_seq) AS rows_in_snapshot
        FROM stg.organisation_key_override AS o
        WHERE o.reason = 'coding_error'
    ) AS k
    JOIN dw.dim_release AS fr ON fr.release_seq = k.valid_from_seq
    JOIN dw.dim_release AS tr ON tr.release_seq = k.valid_to_seq
) AS f;
GO
