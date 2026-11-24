-- test: the prior-year audit is complete: every provider-line pair with a prior-year value in year Y and a current-year value in year Y-1 is compared, the listed differences are exactly those of 1 or more recomputed here, and the summary agrees with the list
-- marker: localdata
WITH pairs AS (
    SELECT py.release, py.provider_key, py.line_key, py.value - cy.value AS difference
    FROM dw.tac_fact AS py
    JOIN dw.tac_fact AS cy ON cy.provider_key = py.provider_key AND cy.line_key = py.line_key
                          AND cy.period_column = 'CY' AND cy.release = py.reported_year
    WHERE py.period_column = 'PY'
)
SELECT CAST(NULL AS varchar(7)) AS release, CAST(NULL AS int) AS provider_key, CAST(NULL AS int) AS line_key, 'listed differences are not those recomputed' AS problem
FROM (SELECT (SELECT COUNT(*) FROM pairs WHERE ABS(difference) >= 1) AS expected_n,
             (SELECT COUNT(*) FROM audit.tac_prior_year_difference) AS listed_n,
             (SELECT SUM(difference) FROM pairs WHERE ABS(difference) >= 1) AS expected_sum,
             (SELECT SUM(difference) FROM audit.tac_prior_year_difference) AS listed_sum) AS c
WHERE c.expected_n <> c.listed_n OR ISNULL(c.expected_sum, 0) <> ISNULL(c.listed_sum, 0)
UNION ALL
SELECT NULL, NULL, NULL, 'summary does not count the pairs or the listed differences'
WHERE (SELECT COUNT(*) FROM pairs) <> (SELECT SUM(values_compared) FROM audit.tac_prior_year_summary)
   OR (SELECT SUM(values_differing_by_1_or_more) FROM audit.tac_prior_year_summary) <> (SELECT COUNT(*) FROM audit.tac_prior_year_difference)
UNION ALL
SELECT d.release, d.provider_key, d.line_key, 'a difference is not what the two facts give'
FROM audit.tac_prior_year_difference AS d
WHERE d.difference <> d.prior_year_as_published - d.current_year_as_filed OR ABS(d.difference) < 1
UNION ALL
SELECT release, NULL, NULL, 'the first year has no earlier file to compare with'
FROM audit.tac_prior_year_summary WHERE release = '2019-20';
