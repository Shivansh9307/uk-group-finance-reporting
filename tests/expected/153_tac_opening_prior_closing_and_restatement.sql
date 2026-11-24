-- requires: dw.tac_fact
-- Independent of the model: opening = the prior-year column of the file of the year; prior-year closing = the
-- current-year column of the previous year's file; restatement = for the provider-lines in both, prior-year value less
-- current-year value where they differ by 1 or more. A section adds its lines of kind line (a one-line section is that line).
WITH sec AS (
    SELECT l.line_key, l.section, l.line_kind, COUNT(*) OVER (PARTITION BY l.statement, l.section) AS lines_in_section
    FROM dw.tac_statutory_line AS l WHERE l.statement = 'SoFP'
),
used AS (SELECT line_key, section FROM sec WHERE line_kind = 'line' OR lines_in_section = 1),
yr AS (SELECT DISTINCT release, CONCAT(CAST(LEFT(release, 4) AS int) - 1, '-', RIGHT(CONCAT('0', CAST(SUBSTRING(release, 6, 2) AS int) - 1), 2)) AS release_prior FROM dw.tac_fact),
opening AS (
    SELECT f.release, u.section, SUM(f.value) AS v
    FROM dw.tac_fact AS f JOIN used AS u ON u.line_key = f.line_key
    WHERE f.period_column = 'PY' GROUP BY f.release, u.section
),
prior AS (
    SELECT y.release, u.section, SUM(f.value) AS v
    FROM yr AS y
    JOIN dw.tac_fact AS f ON f.period_column = 'CY' AND f.release = y.release_prior
    JOIN used AS u ON u.line_key = f.line_key
    GROUP BY y.release, u.section
),
restated AS (
    SELECT py.release, u.section, SUM(py.value - cy.value) AS v
    FROM dw.tac_fact AS py
    JOIN dw.tac_fact AS cy ON cy.provider_key = py.provider_key AND cy.line_key = py.line_key AND cy.period_column = 'CY' AND cy.release = py.reported_year
    JOIN used AS u ON u.line_key = py.line_key
    WHERE py.period_column = 'PY' AND ABS(py.value - cy.value) >= 1
    GROUP BY py.release, u.section
)
SELECT o.release AS [Financial Year], o.section AS [Section],
       CAST(o.v AS decimal(38, 4)) AS opening_balance,
       CAST(p.v AS decimal(38, 4)) AS prior_year_closing_balance,
       CAST(o.v - ISNULL(p.v, 0) AS decimal(38, 4)) AS opening_less_prior_closing,
       CAST(r.v AS decimal(38, 4)) AS restatement
FROM opening AS o
LEFT JOIN prior AS p ON p.release = o.release AND p.section = o.section
LEFT JOIN restated AS r ON r.release = o.release AND r.section = o.section
ORDER BY o.release, o.section;
