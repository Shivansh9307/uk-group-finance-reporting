-- test: the residual of each derived line is the derived amount less the published lines compared with it (published recomputed from dw.tac_fact), the section rows are the sums of their lines, the net change row adds every line against the published increase in cash, a derived-only line has no published amount, and the residual is not forced to zero (the operating residual is non-zero in every year, as non-cash adjustments are not on the face of the two statements)
-- marker: localdata
-- requires: audit.tac_cash_flow_line_residual, audit.tac_cash_flow_section_residual
WITH published AS (
    SELECT f.release, c.cash_flow_line_key, SUM(f.value) AS published_total
    FROM dw.tac_fact AS f JOIN dw.tac_cash_flow_comparison AS c ON c.line_key = f.line_key
    WHERE f.period_column = 'CY' GROUP BY f.release, c.cash_flow_line_key
),
derived AS (
    SELECT release, cash_flow_line_key, SUM(amount) AS derived_total FROM dw.tac_cash_flow_derived GROUP BY release, cash_flow_line_key
)
SELECT r.release, r.line_code AS what, 'line residual differs from derived less published' AS problem
FROM audit.tac_cash_flow_line_residual AS r
LEFT JOIN derived AS d ON d.release = r.release AND d.cash_flow_line_key = r.cash_flow_line_key
LEFT JOIN published AS p ON p.release = r.release AND p.cash_flow_line_key = r.cash_flow_line_key
WHERE ABS(r.derived_total - ISNULL(d.derived_total, 0)) >= 0.0001
   OR ABS(r.published_total - ISNULL(p.published_total, 0)) >= 0.0001
   OR ABS(r.residual - (ISNULL(d.derived_total, 0) - ISNULL(p.published_total, 0))) >= 0.0001
UNION ALL
SELECT r.release, r.line_code, 'derived-only line with a published amount, or published-only line with a derived amount'
FROM audit.tac_cash_flow_line_residual AS r
WHERE (r.line_kind = 'derived_only' AND r.published_total <> 0) OR (r.line_kind = 'published_only' AND r.derived_total <> 0)
UNION ALL
SELECT s.release, s.section, 'section row differs from the sum of its lines'
FROM audit.tac_cash_flow_section_residual AS s
JOIN (SELECT release, section, SUM(derived_total) AS d, SUM(published_total) AS p, SUM(residual) AS r
      FROM audit.tac_cash_flow_line_residual GROUP BY release, section) AS l ON l.release = s.release AND l.section = s.section
WHERE ABS(s.derived_total - l.d) >= 0.0001 OR ABS(s.published_total - l.p) >= 0.0001 OR ABS(s.residual - l.r) >= 0.0001
UNION ALL
-- the published side of the three activity sections equals the published subtotals of the form, to the rounding of the forms
SELECT s.release, s.section, 'published side of a section differs from the published subtotal'
FROM audit.tac_cash_flow_section_residual AS s
JOIN (SELECT f.release, l.section, SUM(f.value) AS sub_total
      FROM dw.tac_fact AS f JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key AND l.sub_code IN ('SCF0180', 'SCF0240', 'SCF0315')
      WHERE f.period_column = 'CY' GROUP BY f.release, l.section) AS q ON q.release = s.release AND q.section = s.section
WHERE ABS(s.published_total - q.sub_total) >= 1
UNION ALL
SELECT s.release, s.section, 'net change row is not the sum of the lines, or not set against the published increase in cash'
FROM audit.tac_cash_flow_section_residual AS s
WHERE s.section = N'Net change in cash'
  AND (ABS(s.derived_total - (SELECT SUM(x.derived_total) FROM audit.tac_cash_flow_line_residual AS x WHERE x.release = s.release)) >= 0.0001
       OR ABS(s.published_total - (SELECT SUM(f.value) FROM dw.tac_fact AS f JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key
                                   WHERE f.release = s.release AND f.period_column = 'CY' AND l.sub_code = 'SCF0320')) >= 0.0001)
UNION ALL
SELECT s.release, s.section, 'operating residual is zero (the tables must not force a tie)'
FROM audit.tac_cash_flow_section_residual AS s
WHERE s.section = N'Operating activities' AND ABS(s.residual) < 1000
UNION ALL
SELECT 'all', 'rows', 'a residual table does not have one row per year and line, or per year and section'
WHERE (SELECT COUNT(*) FROM audit.tac_cash_flow_line_residual) <> 6 * 22
   OR (SELECT COUNT(*) FROM audit.tac_cash_flow_section_residual) <> 6 * 5;
