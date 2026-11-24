-- scope: full
-- audit.forecast_return_summary: one row per financial year, what the load produced and how it was checked.
--   returns               returns loaded (R0 to R13; FY2021-22 has no R0)
--   rows_periods_1_12     rows of dw.forecast_return at periods 1 to 12 (the load grain), all returns of the year
--   rows_period_0         rows at period 0 (budget adjustments), kept and flagged, never in a total
--   quarantined_cells     cells whose organisation code could not be given a key (quarantine.forecast_return_unmapped)
--   flagged_returns       returns with at least one row in dw.forecast_return_quality
--   flagged_rows          rows in dw.forecast_return_quality (one per rule, return and organisation or department group)
--   r13_control_rows_diff, r13_control_amount_diff
--                         the sum over the twelve months (and period 0) of R13 of |loaded - independent recomputation|, rows
--                         and exact amount in GBP thousands; 0 and 0 means the load ties to a recomputation that shares no
--                         code with the reader (data/audit/forecast_independent_control.csv)
--   all_returns_control_amount_diff   the same over all returns of the year
--   r13_total_dw          R13 months 1 to 12, every budget, as dw.forecast_return holds it (DECIMAL(19,4), each grain row
--                         rounded once)
--   r13_total_exact       the same from the exact sums of the cells

DROP TABLE IF EXISTS audit.forecast_return_summary;
GO

CREATE TABLE audit.forecast_return_summary (
    financial_year                  varchar(7)     NOT NULL,
    family                          varchar(10)    NOT NULL,
    returns                         int            NOT NULL,
    rows_periods_1_12               int            NOT NULL,
    rows_period_0                   int            NOT NULL,
    quarantined_cells               int            NOT NULL,
    flagged_returns                 int            NOT NULL,
    flagged_rows                    int            NOT NULL,
    r13_control_rows_diff           bigint         NOT NULL,
    r13_control_amount_diff         decimal(38,16) NOT NULL,
    all_returns_control_amount_diff decimal(38,16) NOT NULL,
    r13_total_dw                    decimal(19,4)  NOT NULL,
    r13_total_exact                 decimal(38,16) NOT NULL,
    CONSTRAINT pk_audit_forecast_return_summary PRIMARY KEY (financial_year)
);
GO

WITH loaded AS (
    SELECT f.family, f.financial_year, c.return_no, c.period, SUM(CAST(c.source_rows AS bigint)) AS data_rows, SUM(c.amount) AS amount
    FROM raw.forecast_return_cell AS c
    JOIN raw.forecast_return_file AS f ON f.file_id = c.file_id
    GROUP BY f.family, f.financial_year, c.return_no, c.period
),
ctl AS (
    SELECT COALESCE(l.financial_year, e.financial_year) AS financial_year, COALESCE(l.return_no, e.return_no) AS return_no,
           ABS(COALESCE(l.data_rows, 0) - COALESCE(e.data_rows, 0)) AS rows_diff,
           ABS(COALESCE(l.amount, 0) - COALESCE(CAST(e.amount_sum AS decimal(38, 16)), 0)) AS amount_diff
    FROM loaded AS l
    FULL OUTER JOIN raw.forecast_return_expected AS e
      ON e.family = l.family AND e.financial_year = l.financial_year AND e.return_no = l.return_no AND e.period = l.period
),
ctl_year AS (
    SELECT financial_year,
           SUM(CASE WHEN return_no = 13 THEN rows_diff ELSE 0 END) AS r13_rows_diff,
           SUM(CASE WHEN return_no = 13 THEN amount_diff ELSE 0 END) AS r13_amount_diff,
           SUM(amount_diff) AS all_amount_diff
    FROM ctl GROUP BY financial_year
)
INSERT INTO audit.forecast_return_summary
    (financial_year, family, returns, rows_periods_1_12, rows_period_0, quarantined_cells, flagged_returns, flagged_rows,
     r13_control_rows_diff, r13_control_amount_diff, all_returns_control_amount_diff, r13_total_dw, r13_total_exact)
SELECT h.financial_year, MIN(h.family), COUNT(*), SUM(h.rows_periods_1_12), SUM(h.rows_period_0), SUM(h.quarantined_cells),
       (SELECT COUNT(DISTINCT q.return_no) FROM dw.forecast_return_quality AS q WHERE q.financial_year = h.financial_year),
       (SELECT COUNT(*) FROM dw.forecast_return_quality AS q WHERE q.financial_year = h.financial_year),
       MAX(cy.r13_rows_diff), MAX(cy.r13_amount_diff), MAX(cy.all_amount_diff),
       SUM(CASE WHEN h.return_no = 13 THEN h.total_periods_1_12 ELSE 0 END),
       COALESCE((SELECT SUM(c.amount_exact) FROM stg.forecast_return_cell AS c
                 WHERE c.financial_year = h.financial_year AND c.return_no = 13 AND c.period BETWEEN 1 AND 12), 0)
FROM dw.forecast_return_header AS h
JOIN ctl_year AS cy ON cy.financial_year = h.financial_year
GROUP BY h.financial_year;
GO
