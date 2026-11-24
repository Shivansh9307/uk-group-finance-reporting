-- requires: dw.tac_fact
-- Independent of the model: the all-rows column is the net difference of audit.tac_prior_year_summary (the audit of
-- the prior year against the year before, differences of 1 or more); the lines-only column is the same differences
-- restricted to the lines of kind line, recomputed from audit.tac_prior_year_difference and dw.tac_statutory_line.
SELECT s.release AS [Financial Year], s.statement AS [Statement Code],
       CAST(d.lines_only AS decimal(38, 4)) AS restatement_lines_only,
       CAST(s.net_difference AS decimal(38, 4)) AS restatement_all_rows
FROM audit.tac_prior_year_summary AS s
LEFT JOIN (SELECT x.release, x.statement, SUM(x.difference) AS lines_only
           FROM audit.tac_prior_year_difference AS x
           JOIN dw.tac_statutory_line AS l ON l.line_key = x.line_key AND l.line_kind = 'line'
           GROUP BY x.release, x.statement) AS d ON d.release = s.release AND d.statement = s.statement
WHERE s.values_differing_by_1_or_more > 0
ORDER BY s.release, s.statement;
