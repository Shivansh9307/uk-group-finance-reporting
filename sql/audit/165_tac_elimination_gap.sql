-- scope: full
-- audit.tac_elimination_gap: the sum of the NHS provider accounts against the consolidated NHS provider accounts, per
-- file year and control line, GBP thousand, TAC sign (income and assets positive, expenses and liabilities negative,
-- as printed in both).
--   tac_sum         the provider values of the control line's statement lines (never a subtotal or a total) added over
--                   the providers (current-year column)
--   consolidated    the printed consolidated lines of the control line added, GBP million printed times 1,000
--   gap             tac_sum less consolidated: what the consolidation takes out (intra-NHS income and expense,
--                   balances between providers) and whatever else differs between the two populations, which this
--                   table does not separate
--   gap_percent     the gap as a percentage of the consolidated figure
--   providers       the providers with a value in the year
--   pages           the printed page of the consolidated statement each figure is keyed from
--   audit.tac_elimination_gap_excluded
--                   a partial explanation of the gap, from the provider side only: a provider whose accounts the TAC file
--                   leaves out ("excluded from this dataset") is in the consolidated accounts all the same. Its figures
--                   are read from the prior-year column of the next year's file, when that provider reports again.
--                   One row per excluded year and control line: providers excluded, providers with a prior-year column
--                   to read, and their values added, TAC sign, GBP thousand.
-- The consolidated figures are authored (hand-keyed, authored/tac_consolidated_control.csv); the provider side is real.
-- The gap is a difference of the two, never added to either.

DROP TABLE IF EXISTS audit.tac_elimination_gap;
GO

WITH tac AS (
    SELECT f.release, m.control_line_key, CAST(SUM(f.value) AS decimal(19,4)) AS tac_sum,
           COUNT(DISTINCT f.provider_key) AS providers
    FROM dw.tac_fact AS f
    JOIN dw.tac_control_member AS m ON m.line_key = f.line_key
    WHERE f.period_column = 'CY'
    GROUP BY f.release, m.control_line_key
),
con AS (
    SELECT release, control_line_key, CAST(SUM(amount) AS decimal(19,4)) AS consolidated,
           MIN(printed_page) AS printed_page_first, MAX(printed_page) AS printed_page_last
    FROM dw.tac_consolidated_control
    GROUP BY release, control_line_key
)
SELECT CAST(t.release AS varchar(7)) AS release, c.control_line_key, c.control_line, c.label, c.nature,
       t.tac_sum, k.consolidated, CAST(t.tac_sum - k.consolidated AS decimal(19,4)) AS gap,
       CAST(100 * CAST(t.tac_sum - k.consolidated AS decimal(30,10)) / NULLIF(CAST(k.consolidated AS decimal(30,10)), 0) AS decimal(19,6)) AS gap_percent,
       t.providers,
       CAST(CASE WHEN k.printed_page_first = k.printed_page_last THEN CAST(k.printed_page_first AS varchar(10))
                 ELSE CONCAT(k.printed_page_first, '-', k.printed_page_last) END AS varchar(20)) AS pages
INTO audit.tac_elimination_gap
FROM tac AS t
JOIN con AS k ON k.release = t.release AND k.control_line_key = t.control_line_key
JOIN dw.tac_control_line AS c ON c.control_line_key = t.control_line_key;
GO
ALTER TABLE audit.tac_elimination_gap ALTER COLUMN release varchar(7) NOT NULL;
GO
ALTER TABLE audit.tac_elimination_gap ADD CONSTRAINT pk_audit_tac_elimination_gap PRIMARY KEY (release, control_line_key);
GO

DROP TABLE IF EXISTS audit.tac_elimination_gap_excluded;
GO
SELECT CAST(y.release AS varchar(7)) AS release, m.control_line_key,
       COUNT(DISTINCT y.provider_key) AS providers_excluded_with_prior_year_column,
       CAST(SUM(f.value) AS decimal(19,4)) AS value_from_next_year_prior_column,
       CAST((SELECT COUNT(*) FROM dw.tac_provider_year AS e WHERE e.release = y.release AND e.list_status = 'excluded') AS int) AS providers_excluded
INTO audit.tac_elimination_gap_excluded
FROM dw.tac_provider_year AS y
JOIN dw.tac_fact AS f ON f.provider_key = y.provider_key AND f.period_column = 'PY' AND f.reported_year = y.release
JOIN dw.tac_control_member AS m ON m.line_key = f.line_key
WHERE y.list_status = 'excluded'
GROUP BY y.release, m.control_line_key;
GO
ALTER TABLE audit.tac_elimination_gap_excluded ALTER COLUMN release varchar(7) NOT NULL;
GO
ALTER TABLE audit.tac_elimination_gap_excluded ADD CONSTRAINT pk_audit_tac_elimination_gap_excluded PRIMARY KEY (release, control_line_key);
GO
