-- stg.outturn_line_snapshot: what each in-year release reports, on warehouse keys, one row per release and
-- line. The file is in dw/ because it needs the dimension keys; the object is in stg because it is a
-- working table, not something the model reads.
--   line   = (organisation_key, segment_key, account_key, control_budget_key, period_key). period_key
--            carries the financial year, so a line never spans two years.
--   release_seq   the release; each release reports one financial year to date
--   department_key   the department the release reports for the line (it is the same in every release
--                    that reports the line: tested)
--   amount   DECIMAL(19,4), GBP thousands. Rows that are 0.0000 (exact zeros are already dropped by the
--            stage; 58 float-residue rows round to 0.0000) do not exist here: absent and zero mean the
--            same thing.
-- Keys are those of dw.organisation_release_map, not source codes, so "as at release R" is exactly what
-- release R reports even where an organisation's version changes between two releases of one year.

DROP TABLE IF EXISTS stg.outturn_line_snapshot;
GO

CREATE TABLE stg.outturn_line_snapshot (
    release_seq          int           NOT NULL,
    organisation_key     int           NOT NULL,
    segment_key          int           NOT NULL,
    account_key          int           NOT NULL,
    control_budget_key   int           NOT NULL,
    period_key           int           NOT NULL,
    department_key       int           NOT NULL,
    amount               decimal(19,4) NOT NULL,
    CONSTRAINT pk_stg_outturn_line_snapshot PRIMARY KEY CLUSTERED
        (release_seq, organisation_key, segment_key, account_key, control_budget_key, period_key)
);
GO

INSERT INTO stg.outturn_line_snapshot WITH (TABLOCK)
    (release_seq, organisation_key, segment_key, account_key, control_budget_key, period_key, department_key, amount)
SELECT m.release_seq, m.organisation_key, sg.segment_key, ac.account_key, cb.control_budget_key,
       CAST(LEFT(s.financial_year, 4) AS int) * 100 + s.period,
       MAX(m.department_key),
       SUM(s.amount)
FROM stg.inyear_snapshot AS s
JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
JOIN dw.dim_segment AS sg ON sg.sub_segment_code = s.sub_segment_code
JOIN dw.dim_account AS ac ON ac.economic_category_code = CASE WHEN s.economic_category_code = 'n/a' THEN 'NA' ELSE s.economic_category_code END
JOIN dw.dim_control_budget AS cb ON cb.control_budget_detail_code = s.control_budget_detail_code
GROUP BY m.release_seq, m.organisation_key, sg.segment_key, ac.account_key, cb.control_budget_key,
         CAST(LEFT(s.financial_year, 4) AS int) * 100 + s.period
HAVING SUM(s.amount) <> 0
ORDER BY m.release_seq, m.organisation_key, sg.segment_key, ac.account_key, cb.control_budget_key,
         CAST(LEFT(s.financial_year, 4) AS int) * 100 + s.period;
GO
