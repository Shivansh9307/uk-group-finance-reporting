-- scope: full
-- dw.forecast_return_header: one row per return (financial year x return number), 83 rows. What the return holds, from
-- the loaded rows and from dw.forecast_return, so that a reader sees the size of every return before using it.
--   year_seq             1.. in financial-year order (FY2017-18 = 1); the prior year of year_seq n is n - 1
--   family               extract (FY2017-18 to FY2020-21, from the annual extracts) | mfo (FY2021-22, FY2022-23)
--   source_rows          data records of the return that the load read, all periods (raw.forecast_return_file)
--   rows_periods_1_12    rows of dw.forecast_return at periods 1 to 12 (the load grain, the number the profiling predicted)
--   rows_period_0        rows at period 0 (budget adjustments; R13 of the extracts only)
--   quarantined_cells    cells in quarantine.forecast_return_unmapped
--   organisations, department_groups  distinct in periods 1 to 12
--   months_present       distinct periods 1 to 12 with a row (12 in every return)
--   total_periods_1_12   the return's total: periods 1 to 12, every budget, every status, GBP thousands. Period 0 is never in it.
--   is_final             R13, the final outturn of the family

DROP TABLE IF EXISTS dw.forecast_return_header;
GO

CREATE TABLE dw.forecast_return_header (
    financial_year       varchar(7)     NOT NULL,
    return_no            tinyint        NOT NULL,
    year_seq             int            NOT NULL,
    family               varchar(10)    NOT NULL,
    source_rows          int            NOT NULL,
    rows_periods_1_12    int            NOT NULL,
    rows_period_0        int            NOT NULL,
    quarantined_cells    int            NOT NULL,
    organisations        int            NOT NULL,
    department_groups    int            NOT NULL,
    months_present       tinyint        NOT NULL,
    total_periods_1_12   decimal(19,4)  NOT NULL,
    is_final             bit            NOT NULL,
    CONSTRAINT pk_dw_forecast_return_header PRIMARY KEY (financial_year, return_no),
    CONSTRAINT uq_dw_forecast_return_header_seq UNIQUE (year_seq, return_no)
);
GO

INSERT INTO dw.forecast_return_header
    (financial_year, return_no, year_seq, family, source_rows, rows_periods_1_12, rows_period_0, quarantined_cells,
     organisations, department_groups, months_present, total_periods_1_12, is_final)
SELECT f.financial_year, f.return_no,
       DENSE_RANK() OVER (ORDER BY f.financial_year),
       f.family, f.source_rows,
       COALESCE(a.rows_periods_1_12, 0), COALESCE(a.rows_period_0, 0),
       COALESCE(q.quarantined_cells, 0),
       COALESCE(a.organisations, 0), COALESCE(a.department_groups, 0), COALESCE(a.months_present, 0),
       COALESCE(a.total_periods_1_12, 0),
       CASE WHEN f.return_no = 13 THEN 1 ELSE 0 END
FROM raw.forecast_return_file AS f
LEFT JOIN (
    SELECT r.financial_year, r.return_no,
           SUM(CASE WHEN r.period BETWEEN 1 AND 12 THEN 1 ELSE 0 END) AS rows_periods_1_12,
           SUM(CASE WHEN r.period = 0 THEN 1 ELSE 0 END) AS rows_period_0,
           COUNT(DISTINCT CASE WHEN r.period BETWEEN 1 AND 12 THEN r.organisation_code END) AS organisations,
           COUNT(DISTINCT CASE WHEN r.period BETWEEN 1 AND 12 THEN r.department_group_code END) AS department_groups,
           COUNT(DISTINCT CASE WHEN r.period BETWEEN 1 AND 12 THEN r.period END) AS months_present,
           SUM(CASE WHEN r.period BETWEEN 1 AND 12 THEN r.amount ELSE 0 END) AS total_periods_1_12
    FROM dw.forecast_return AS r
    GROUP BY r.financial_year, r.return_no
) AS a ON a.financial_year = f.financial_year AND a.return_no = f.return_no
LEFT JOIN (
    SELECT financial_year, return_no, COUNT(*) AS quarantined_cells FROM quarantine.forecast_return_unmapped
    GROUP BY financial_year, return_no
) AS q ON q.financial_year = f.financial_year AND q.return_no = f.return_no;
GO
