-- scope: full
-- audit.forecast_r13_vs_outturn: R13 of the forecast returns (months 1 to 12, the final outturn of the family) against the
-- outturn that dw already holds for the same year, for FY2018-19 to FY2022-23. A comparison, not a gate: the differences
-- are explained in docs/data-dictionary/forecast-returns.md.
--   source  'annual <vintage>'  dw.fact_outturn_annual of that BUD vintage (every TYPE layer, Closed rows excluded; the
--                               annual files carry no month, so they include the budget adjustments that the returns keep
--                               in period 0)
--           'in-year <release>' stg.inyear_snapshot of the year-end release (the June release of the next year, periods
--                               1 to 12), a snapshot taken before the final revisions
--   level   DEL (programme and administration), DEPT AME, NON-DEPT AME, NON-BUDGET, TOTAL
--   r13_amount, other_amount in GBP thousands, DECIMAL(19,4); gap = r13 - other; gap_share_of_other = gap / other
-- R13 is summed from stg.forecast_return_cell (every cell, including any that quarantine.forecast_return_unmapped holds),
-- so the comparison does not depend on the organisation mapping.

DROP TABLE IF EXISTS audit.forecast_r13_vs_outturn;
GO

CREATE TABLE audit.forecast_r13_vs_outturn (
    financial_year       varchar(7)     NOT NULL,
    source               varchar(30)    NOT NULL,
    level                varchar(15)    NOT NULL,
    r13_amount           decimal(19,4)  NOT NULL,
    other_amount         decimal(19,4)  NOT NULL,
    gap                  decimal(19,4)  NOT NULL,
    gap_share_of_other   decimal(19,10) NULL,
    CONSTRAINT pk_audit_forecast_r13_vs_outturn PRIMARY KEY (financial_year, source, level)
);
GO

WITH r13 AS (
    SELECT c.financial_year,
           CASE WHEN c.control_budget_detail IN ('DEL PROG', 'DEL ADMIN') THEN 'DEL' ELSE c.control_budget_detail END AS level,
           CAST(ROUND(SUM(c.amount_exact), 4) AS decimal(19, 4)) AS amount
    FROM stg.forecast_return_cell AS c
    WHERE c.return_no = 13 AND c.period BETWEEN 1 AND 12 AND c.financial_year >= '2018-19'
    GROUP BY c.financial_year,
             CASE WHEN c.control_budget_detail IN ('DEL PROG', 'DEL ADMIN') THEN 'DEL' ELSE c.control_budget_detail END
),
other AS (
    SELECT a.financial_year, CONCAT('annual ', a.vintage) AS source,
           CASE WHEN a.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN') THEN 'DEL' ELSE a.control_budget_detail_code END AS level,
           SUM(a.amount) AS amount
    FROM dw.fact_outturn_annual AS a
    WHERE a.financial_year BETWEEN '2018-19' AND '2022-23'
    GROUP BY a.financial_year, a.vintage,
             CASE WHEN a.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN') THEN 'DEL' ELSE a.control_budget_detail_code END
    UNION ALL
    SELECT s.financial_year, CONCAT('in-year ', s.release),
           CASE WHEN s.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN') THEN 'DEL' ELSE s.control_budget_detail_code END,
           SUM(s.amount)
    FROM stg.release AS y
    JOIN stg.inyear_snapshot AS s ON s.release = y.release AND s.financial_year = y.financial_year
    WHERE y.highest_period = 12 AND s.period BETWEEN 1 AND 12 AND s.financial_year BETWEEN '2018-19' AND '2022-23'
    GROUP BY s.financial_year, s.release,
             CASE WHEN s.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN') THEN 'DEL' ELSE s.control_budget_detail_code END
),
joined AS (
    SELECT o.financial_year, o.source, o.level, COALESCE(r.amount, 0) AS r13_amount, o.amount AS other_amount
    FROM other AS o
    LEFT JOIN r13 AS r ON r.financial_year = o.financial_year AND r.level = o.level
    WHERE o.level IN ('DEL', 'DEPT AME', 'NON-DEPT AME', 'NON-BUDGET')
)
INSERT INTO audit.forecast_r13_vs_outturn (financial_year, source, level, r13_amount, other_amount, gap, gap_share_of_other)
SELECT financial_year, source, level, r13_amount, other_amount, r13_amount - other_amount,
       CASE WHEN other_amount <> 0 THEN CAST(r13_amount - other_amount AS decimal(30, 10)) / other_amount END
FROM joined
UNION ALL
SELECT financial_year, source, 'TOTAL', SUM(r13_amount), SUM(other_amount), SUM(r13_amount) - SUM(other_amount),
       CASE WHEN SUM(other_amount) <> 0 THEN CAST(SUM(r13_amount) - SUM(other_amount) AS decimal(30, 10)) / SUM(other_amount) END
FROM joined
GROUP BY financial_year, source;
GO
