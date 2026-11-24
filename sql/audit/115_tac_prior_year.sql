-- scope: full
-- Prior-year comparison. The prior-year column (PY) of year Y should equal the current-year column (CY) of year Y-1
-- for a provider that has data in both files. A difference is a restatement, a reclassification or a change of the
-- provider's group (a merger), and these are real in published accounts.
--   audit.tac_prior_year_difference  one row per provider, year and line where PY of Y differs from CY of Y-1 by
--                                    1 (GBP 1,000) or more. Smaller differences (the rounding of the thousand) are
--                                    counted in the summary, not listed.
--   audit.tac_prior_year_summary     one row per year and statement: values compared, values that differ at all,
--                                    values that differ by 1 or more, providers compared, providers with any such
--                                    difference, and the net and absolute sums of the differences of 1 or more.
-- The first year (2019-20) has no earlier file; a provider missing from the earlier file (new, or excluded that
-- year) is not compared. Both are visible in providers_compared.

DROP TABLE IF EXISTS audit.tac_prior_year_difference;
GO
DROP TABLE IF EXISTS audit.tac_prior_year_summary;
GO

CREATE TABLE audit.tac_prior_year_difference (
    release            varchar(7)    NOT NULL,
    provider_key       int           NOT NULL,
    line_key           int           NOT NULL,
    provider_code      nvarchar(20)  NOT NULL,
    statement          varchar(4)    NOT NULL,
    sub_code           varchar(20)   NOT NULL,
    prior_year_as_published decimal(19,4) NOT NULL,   -- PY column in the file of `release`
    current_year_as_filed   decimal(19,4) NOT NULL,   -- CY column in the file of the year before
    difference         decimal(19,4) NOT NULL,
    CONSTRAINT pk_audit_tac_prior_year_difference PRIMARY KEY (release, provider_key, line_key)
);
GO


INSERT INTO audit.tac_prior_year_difference
    (release, provider_key, line_key, provider_code, statement, sub_code, prior_year_as_published,
     current_year_as_filed, difference)
SELECT x.release, x.provider_key, x.line_key, p.provider_code, l.statement, l.sub_code, x.py_value, x.cy_value, x.difference
FROM (SELECT py.release, py.provider_key, py.line_key, py.value AS py_value, cy.value AS cy_value, py.value - cy.value AS difference
     FROM dw.tac_fact AS py
     JOIN dw.tac_fact AS cy ON cy.provider_key = py.provider_key AND cy.line_key = py.line_key
                           AND cy.period_column = 'CY' AND cy.release = py.reported_year
     WHERE py.period_column = 'PY') AS x
JOIN dw.tac_provider AS p ON p.provider_key = x.provider_key
JOIN dw.tac_statutory_line AS l ON l.line_key = x.line_key
WHERE ABS(x.difference) >= 1;
GO

SELECT x.release, l.statement,
       COUNT_BIG(*) AS values_compared,
       SUM(CASE WHEN x.difference <> 0 THEN 1 ELSE 0 END) AS values_differing,
       SUM(CASE WHEN ABS(x.difference) >= 1 THEN 1 ELSE 0 END) AS values_differing_by_1_or_more,
       COUNT(DISTINCT x.provider_key) AS providers_compared,
       COUNT(DISTINCT CASE WHEN ABS(x.difference) >= 1 THEN x.provider_key END) AS providers_differing_by_1_or_more,
       SUM(CASE WHEN ABS(x.difference) >= 1 THEN x.difference ELSE 0 END) AS net_difference,
       SUM(CASE WHEN ABS(x.difference) >= 1 THEN ABS(x.difference) ELSE 0 END) AS absolute_difference
INTO audit.tac_prior_year_summary
FROM (SELECT py.release, py.provider_key, py.line_key, py.value AS py_value, cy.value AS cy_value, py.value - cy.value AS difference
     FROM dw.tac_fact AS py
     JOIN dw.tac_fact AS cy ON cy.provider_key = py.provider_key AND cy.line_key = py.line_key
                           AND cy.period_column = 'CY' AND cy.release = py.reported_year
     WHERE py.period_column = 'PY') AS x
JOIN dw.tac_statutory_line AS l ON l.line_key = x.line_key
GROUP BY x.release, l.statement;
GO

ALTER TABLE audit.tac_prior_year_summary ALTER COLUMN release varchar(7) NOT NULL;
GO
ALTER TABLE audit.tac_prior_year_summary ALTER COLUMN statement varchar(4) NOT NULL;
GO
ALTER TABLE audit.tac_prior_year_summary ADD CONSTRAINT pk_audit_tac_prior_year_summary PRIMARY KEY (release, statement);
GO
