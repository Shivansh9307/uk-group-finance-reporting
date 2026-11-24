-- requires: dw.tac_fact
-- Independent of the model: from dw.tac_fact and dw.tac_cash_flow_derived. The published increase in cash is the
-- current-year value of SCF0320; the balance sheet movement is the current-year less the prior-year column of BAL1240
-- of the same file, added over the providers.
SELECT d.release AS [Financial Year],
       CAST(d.derived AS decimal(38, 4)) AS derived_net_change,
       CAST(p.published AS decimal(38, 4)) AS published_net_change,
       CAST(b.movement AS decimal(38, 4)) AS balance_sheet_cash_movement,
       CAST(d.derived - p.published AS decimal(38, 4)) AS residual
FROM (SELECT release, SUM(amount) AS derived FROM dw.tac_cash_flow_derived GROUP BY release) AS d
JOIN (SELECT f.release, SUM(f.value) AS published
      FROM dw.tac_fact AS f JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key AND l.sub_code = 'SCF0320'
      WHERE f.period_column = 'CY' GROUP BY f.release) AS p ON p.release = d.release
JOIN (SELECT f.release, SUM(CASE WHEN f.period_column = 'CY' THEN f.value ELSE -f.value END) AS movement
      FROM dw.tac_fact AS f JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key AND l.sub_code = 'BAL1240'
      GROUP BY f.release) AS b ON b.release = d.release
ORDER BY d.release;
