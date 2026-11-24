-- scope: full
-- How the four methods score on the pay line where the workforce paybill is close to the whole of the pay line, and where it is not.
-- POST HOC: I chose the band 0.8 to 1.25 (inclusive) AFTER I had seen the coverage table (audit.forecast_fte_cost_coverage), to ask whether
-- FTE x cost is poor only because it sees a small part of the pay line. The band was not fixed before looking and no other band was tried.
-- The share is known when a forecast is made: the workforce paybill of the last actual month over the return's pay line of that month.
-- Cells: pay line, returns R1 to R11, scored by all four methods, outside the returns flagged in dw.forecast_return_quality.
-- WAPE is a ratio of sums over the cells of the band. Amounts are GBP thousands.

DROP TABLE IF EXISTS audit.forecast_fte_cost_cover_band;
GO

CREATE TABLE audit.forecast_fte_cost_cover_band (
    cover_band   varchar(20)    NOT NULL,   -- 'share 0.8 to 1.25' | 'other'
    method       varchar(10)    NOT NULL,
    cells        int            NOT NULL,
    abs_error    decimal(19,4)  NOT NULL,
    abs_outturn  decimal(19,4)  NOT NULL,
    wape         decimal(19,10) NOT NULL,
    CONSTRAINT pk_audit_forecast_fte_cost_cover_band PRIMARY KEY (cover_band, method)
);
GO

WITH x AS (
    SELECT a.*, COUNT(*) OVER (PARTITION BY a.financial_year, a.return_no, a.department_group_code) AS n_methods
    FROM dw.forecast_pay_accuracy AS a
)
INSERT INTO audit.forecast_fte_cost_cover_band (cover_band, method, cells, abs_error, abs_outturn, wape)
SELECT CASE WHEN c.pay_cover_share BETWEEN 0.8 AND 1.25 THEN 'share 0.8 to 1.25' ELSE 'other' END, x.method, COUNT(*),
       SUM(x.full_year_abs_error), SUM(x.full_year_abs_outturn),
       CAST(CAST(SUM(x.full_year_abs_error) AS decimal(19, 4)) / CAST(SUM(x.full_year_abs_outturn) AS decimal(19, 4)) AS decimal(19, 10))   -- (19,4) over (19,4) keeps 19 places
FROM x
JOIN audit.forecast_fte_cost_coverage AS c
  ON c.financial_year = x.financial_year AND c.return_no = x.return_no AND c.department_group_code = x.department_group_code
 AND c.status = 'covered'
WHERE x.n_methods = 4 AND x.is_flagged_return = 0 AND x.return_no BETWEEN 1 AND 11
GROUP BY CASE WHEN c.pay_cover_share BETWEEN 0.8 AND 1.25 THEN 'share 0.8 to 1.25' ELSE 'other' END, x.method;
GO
