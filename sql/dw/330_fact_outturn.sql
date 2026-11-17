-- dw.fact_outturn: the revision-delta fact for in-year outturn.
--
-- A line is (organisation_key, segment_key, account_key, control_budget_key, period_key). Each in-year
-- release reports one financial year to date, so for release R and a line the delta is
--     amount in R  -  amount in the previous release of the same financial year   (0 if absent there)
-- and only non-zero deltas are stored. A line reported before and absent in R gets a negative delta that
-- reverses it. A line whose organisation key changes between two releases of one year is minus under the
-- old key and plus under the new key (intended: the key is part of the line).
-- The amount "as at release R" is therefore SUM(amount_delta) over release_seq <= R for R's financial
-- year, and it equals exactly what release R reports (tested at full grain, by department and in total).
--
--   release_key              dw.dim_release (= release_seq)
--   organisation_key         dw.dim_organisation, the version the release used
--   department_key           the department as that release reports it (dw.dim_department)
--   current_department_key   stg.current_structure_map: the department in the current structure
--   segment_key, account_key, control_budget_key, period_key, scenario_key (1 = Outturn)
--   amount_delta             DECIMAL(19,4), GBP thousands, spending positive, income negative
--   revision_no              0 on the first delta row of a line, then 1, 2 ... "as first reported" is revision 0
--   dq_issue_id              the unit-error finding (rule a in dw.dq_issue) the row belongs to, else NULL: the
--                            row that corrected the error and the row that set the wrong amount
-- There are no foreign key constraints: the dimension tables are rebuilt by earlier files in the same run
-- and a test proves that every key resolves.

DROP TABLE IF EXISTS dw.fact_outturn;
GO

CREATE TABLE dw.fact_outturn (
    release_key             int           NOT NULL,
    organisation_key        int           NOT NULL,
    department_key          int           NOT NULL,
    current_department_key  int           NOT NULL,
    segment_key             int           NOT NULL,
    account_key             int           NOT NULL,
    control_budget_key      int           NOT NULL,
    period_key              int           NOT NULL,
    scenario_key            int           NOT NULL,
    amount_delta            decimal(19,4) NOT NULL,
    revision_no             smallint      NOT NULL,
    dq_issue_id             int           NULL
);
GO
CREATE CLUSTERED COLUMNSTORE INDEX cci_dw_fact_outturn ON dw.fact_outturn;
GO

-- each snapshot row adds its amount to its own release and takes it away from the next release of the same year
SELECT release_seq, organisation_key, segment_key, account_key, control_budget_key, period_key, department_key, amount
INTO #contrib
FROM (
    SELECT s.release_seq, s.organisation_key, s.segment_key, s.account_key, s.control_budget_key, s.period_key, s.department_key, s.amount
    FROM stg.outturn_line_snapshot AS s
    UNION ALL
    SELECT n.release_seq, s.organisation_key, s.segment_key, s.account_key, s.control_budget_key, s.period_key, s.department_key, -s.amount
    FROM stg.outturn_line_snapshot AS s
    JOIN dw.dim_release AS r ON r.release_seq = s.release_seq
    JOIN dw.dim_release AS n ON n.release_seq = r.release_seq + 1 AND n.financial_year = r.financial_year
) AS u;
GO

SELECT c.release_seq, c.organisation_key, c.segment_key, c.account_key, c.control_budget_key, c.period_key,
       MAX(c.department_key) AS department_key, SUM(c.amount) AS amount_delta
INTO #delta
FROM #contrib AS c
GROUP BY c.release_seq, c.organisation_key, c.segment_key, c.account_key, c.control_budget_key, c.period_key
HAVING SUM(c.amount) <> 0;
GO

SELECT organisation_key, sub_segment_code, current_department_key INTO #csm FROM stg.current_structure_map;
GO

INSERT INTO dw.fact_outturn WITH (TABLOCK)
    (release_key, organisation_key, department_key, current_department_key, segment_key, account_key,
     control_budget_key, period_key, scenario_key, amount_delta, revision_no, dq_issue_id)
SELECT d.release_seq, d.organisation_key, d.department_key, ISNULL(csm.current_department_key, -1),
       d.segment_key, d.account_key, d.control_budget_key, d.period_key, 1, d.amount_delta,
       CAST(ROW_NUMBER() OVER (PARTITION BY d.organisation_key, d.segment_key, d.account_key, d.control_budget_key, d.period_key
                               ORDER BY d.release_seq) - 1 AS smallint),
       q.dq_issue_id
FROM #delta AS d
JOIN dw.dim_segment AS sg ON sg.segment_key = d.segment_key
LEFT JOIN #csm AS csm ON csm.organisation_key = d.organisation_key AND csm.sub_segment_code = sg.sub_segment_code
LEFT JOIN (
    -- the rows of a unit error: the delta row of the line in the release that corrected it, and the latest
    -- delta row of the line at or before the release that first showed the pair (the row that set the amount)
    SELECT i.organisation_key, i.segment_key, i.account_key, i.control_budget_key, i.period_key, k.release_key,
           MIN(i.dq_issue_id) AS dq_issue_id
    FROM dw.dq_issue AS i
    JOIN dw.dim_release AS rf ON rf.label = i.release_from
    JOIN dw.dim_release AS rt ON rt.label = i.release_to
    CROSS APPLY (VALUES
        (rt.release_key),
        ((SELECT MAX(x.release_seq) FROM #delta AS x
          WHERE x.organisation_key = i.organisation_key AND x.segment_key = i.segment_key AND x.account_key = i.account_key
            AND x.control_budget_key = i.control_budget_key AND x.period_key = i.period_key AND x.release_seq <= rf.release_key))
    ) AS k (release_key)
    WHERE i.flags_fact_rows = 1 AND k.release_key IS NOT NULL
    GROUP BY i.organisation_key, i.segment_key, i.account_key, i.control_budget_key, i.period_key, k.release_key
) AS q
  ON q.release_key = d.release_seq AND q.organisation_key = d.organisation_key AND q.segment_key = d.segment_key
 AND q.account_key = d.account_key AND q.control_budget_key = d.control_budget_key AND q.period_key = d.period_key;
GO

DROP TABLE IF EXISTS #contrib;
DROP TABLE IF EXISTS #delta;
DROP TABLE IF EXISTS #csm;
GO
