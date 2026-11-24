-- requires: dw.tac_fact
-- Independent of the model and of audit.tac_elimination_gap: the provider lines of each control line from
-- dw.tac_control_member and dw.tac_fact (current-year column), and the printed values of dw.tac_consolidated_control
-- (GBP million times 1,000) added by control line.
SELECT t.release AS [Financial Year], c.control_line AS [Control Code],
       CAST(t.provider_sum AS decimal(38, 4)) AS provider_sum,
       CAST(k.consolidated AS decimal(38, 4)) AS consolidated,
       CAST(t.provider_sum - k.consolidated AS decimal(38, 4)) AS gap,
       CAST(1000000 * CAST(t.provider_sum - k.consolidated AS decimal(30, 10)) / CAST(k.consolidated AS decimal(30, 10)) AS decimal(38, 4)) AS gap_ppm
FROM (SELECT f.release, m.control_line_key, SUM(f.value) AS provider_sum
      FROM dw.tac_fact AS f JOIN dw.tac_control_member AS m ON m.line_key = f.line_key
      WHERE f.period_column = 'CY' GROUP BY f.release, m.control_line_key) AS t
JOIN (SELECT release, control_line_key, SUM(amount_gbp_million) * 1000 AS consolidated
      FROM dw.tac_consolidated_control GROUP BY release, control_line_key) AS k
  ON k.release = t.release AND k.control_line_key = t.control_line_key
JOIN dw.tac_control_line AS c ON c.control_line_key = t.control_line_key
ORDER BY t.release, c.control_line;
