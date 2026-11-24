-- test: the post hoc comparison of the four methods by how much of the pay line the workforce paybill is (audit.forecast_fte_cost_cover_band, band 0.8 to 1.25 inclusive, chosen after seeing the coverage table) equals a recomputation from dw.forecast_pay_accuracy and dw.forecast_fte_cost_input, where the share is worked out again as the workforce paybill in pounds over 1,000 times the pay line of the month, cells are the pay-line cells of R1 to R11 that all four methods scored outside the flagged returns, and every row has the four methods, each band the same number of cells for each method
-- marker: localdata
-- requires: audit.forecast_fte_cost_cover_band, dw.forecast_pay_accuracy, dw.forecast_fte_cost_input
WITH cells AS (
    SELECT a.financial_year, a.return_no, a.department_group_code
    FROM dw.forecast_pay_accuracy AS a
    WHERE a.return_no BETWEEN 1 AND 11 AND a.is_flagged_return = 0
    GROUP BY a.financial_year, a.return_no, a.department_group_code
    HAVING COUNT(DISTINCT a.method) = 4
),
banded AS (
    SELECT c.financial_year, c.return_no, c.department_group_code,
           CASE WHEN i.pay_month_n > 0 AND i.workforce_paybill_gbp / 1000 / i.pay_month_n >= 0.8
                 AND i.workforce_paybill_gbp / 1000 / i.pay_month_n <= 1.25 THEN 'share 0.8 to 1.25' ELSE 'other' END AS band
    FROM cells AS c
    JOIN dw.forecast_fte_cost_input AS i
      ON i.financial_year = c.financial_year AND i.return_no = c.return_no AND i.department_group_code = c.department_group_code
),
expd AS (
    SELECT b.band, a.method, COUNT_BIG(*) AS cells, SUM(a.full_year_abs_error) AS abs_error, SUM(a.full_year_abs_outturn) AS abs_outturn
    FROM banded AS b
    JOIN dw.forecast_pay_accuracy AS a
      ON a.financial_year = b.financial_year AND a.return_no = b.return_no AND a.department_group_code = b.department_group_code
    GROUP BY b.band, a.method
)
SELECT 'row on one side only' AS problem, COALESCE(e.band, t.cover_band) + ' ' + COALESCE(e.method, t.method) AS detail
FROM expd AS e FULL JOIN audit.forecast_fte_cost_cover_band AS t ON t.cover_band = e.band AND t.method = e.method
WHERE e.band IS NULL OR t.cover_band IS NULL
UNION ALL
SELECT 'cells, errors or WAPE differ', e.band + ' ' + e.method
FROM expd AS e JOIN audit.forecast_fte_cost_cover_band AS t ON t.cover_band = e.band AND t.method = e.method
WHERE e.cells <> t.cells OR e.abs_error <> t.abs_error OR e.abs_outturn <> t.abs_outturn
   OR ABS(t.wape - CAST(e.abs_error AS decimal(30, 10)) / e.abs_outturn) > 0.0000000001
UNION ALL
SELECT 'a band does not have the four methods with the same number of cells', cover_band
FROM audit.forecast_fte_cost_cover_band GROUP BY cover_band HAVING COUNT(*) <> 4 OR MIN(cells) <> MAX(cells);
