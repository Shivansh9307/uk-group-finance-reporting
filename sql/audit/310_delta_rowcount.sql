-- audit.delta_rowcount: the delta rows of dw.fact_outturn per release against the profile's count
-- (docs/profiling/data/inyear_delta_rowcount.csv, column delta_rows_non_zero), with the reason for every
-- difference. Four counts, each computed from a different starting point:
--   profile_rows      the profile, on source codes and exact amounts (landed by the profile_controls stage)
--   exact_cs_rows     the same count recomputed here from raw.oscar_inyear: source codes compared exactly
--                     as written (case sensitive), exact amounts (whole part and fractional part summed
--                     apart, so nothing is rounded). It must equal the profile.
--   exact_code_rows   the same with codes compared as the database compares them (case insensitive)
--   rounded_code_rows source codes, amounts rounded to four decimals as in stg.inyear_snapshot
--   fact_rows         the fact: warehouse keys, rounded amounts
-- Differences and their reasons:
--   case_rows = exact_code_rows - exact_cs_rows   (zero or negative)
--       the sub-segment code x017A064 (2019-03 to 2021-06) is spelled X017A064 from 2020-12. It is one
--       sub-segment: the warehouse compares codes case insensitively, so the line continues across the
--       change of spelling, where a case-sensitive count sees the line vanish and a new one appear
--   rounding_rows = rounded_code_rows - exact_code_rows   (zero or negative)
--       a line whose exact amount changes between two releases by less than 0.0001 (float residue such as
--       1.13687E-13) has a non-zero exact delta and a zero rounded delta, so no row is stored
--   key_rows = fact_rows - rounded_code_rows
--       a line whose organisation key changes between two releases of one year (a new version of the
--       organisation) is minus under the old key and plus under the new one: two rows where the code-level
--       count has one row (amount changed) or none (amount unchanged)
--   key_change_lines_changed / _same   the lines behind key_rows, counted from the release map:
--       expected key_rows = key_change_lines_changed + 2 * key_change_lines_same, and unexplained_rows is
--       the part of key_rows that this does not account for (zero for every release)
--   profile_diff_rows = exact_cs_rows - profile_rows: the independent recomputation against the profile
--       (zero for every release)

DROP TABLE IF EXISTS audit.delta_rowcount;
GO

-- raw, exact: each row adds to its release and is taken away from the next release of the same year
SELECT release_seq, organisation_code, sub_segment_code, economic_category_code, control_budget_detail_code, [month],
       SUM(amount_whole) AS sw, SUM(amount_frac) AS sf
INTO #exact
FROM (
    SELECT r.release_seq, x.organisation_code, x.sub_segment_code, x.economic_category_code, x.control_budget_detail_code, x.[month],
           x.amount_whole, x.amount_frac
    FROM raw.oscar_inyear AS x JOIN stg.release AS r ON r.release = x.release
    UNION ALL
    SELECT n.release_seq, x.organisation_code, x.sub_segment_code, x.economic_category_code, x.control_budget_detail_code, x.[month],
           -x.amount_whole, -x.amount_frac
    FROM raw.oscar_inyear AS x
    JOIN stg.release AS r ON r.release = x.release
    JOIN stg.release AS n ON n.release_seq = r.release_seq + 1 AND n.financial_year = r.financial_year
) AS u
GROUP BY release_seq, organisation_code, sub_segment_code, economic_category_code, control_budget_detail_code, [month];
GO

-- the same, with every code column compared case sensitively
SELECT release_seq, organisation_code, sub_segment_code, economic_category_code, control_budget_detail_code, [month],
       SUM(amount_whole) AS sw, SUM(amount_frac) AS sf
INTO #exact_cs
FROM (
    SELECT r.release_seq, x.organisation_code COLLATE Latin1_General_CS_AS AS organisation_code,
           x.sub_segment_code COLLATE Latin1_General_CS_AS AS sub_segment_code,
           x.economic_category_code COLLATE Latin1_General_CS_AS AS economic_category_code,
           x.control_budget_detail_code COLLATE Latin1_General_CS_AS AS control_budget_detail_code, x.[month],
           x.amount_whole, x.amount_frac
    FROM raw.oscar_inyear AS x JOIN stg.release AS r ON r.release = x.release
    UNION ALL
    SELECT n.release_seq, x.organisation_code COLLATE Latin1_General_CS_AS, x.sub_segment_code COLLATE Latin1_General_CS_AS,
           x.economic_category_code COLLATE Latin1_General_CS_AS, x.control_budget_detail_code COLLATE Latin1_General_CS_AS, x.[month],
           -x.amount_whole, -x.amount_frac
    FROM raw.oscar_inyear AS x
    JOIN stg.release AS r ON r.release = x.release
    JOIN stg.release AS n ON n.release_seq = r.release_seq + 1 AND n.financial_year = r.financial_year
) AS u
GROUP BY release_seq, organisation_code, sub_segment_code, economic_category_code, control_budget_detail_code, [month];
GO

SELECT release_seq, COUNT_BIG(*) AS exact_cs_rows
INTO #exact_cs_count
FROM #exact_cs
WHERE NOT (ABS(sw) <= 1 AND CAST(sw AS decimal(38,31)) + sf = 0)
GROUP BY release_seq;
GO

SELECT release_seq, COUNT_BIG(*) AS exact_code_rows
INTO #exact_count
FROM #exact
WHERE NOT (ABS(sw) <= 1 AND CAST(sw AS decimal(38,31)) + sf = 0)
GROUP BY release_seq;
GO

-- stg, rounded, on source codes
SELECT release_seq, organisation_code, sub_segment_code, economic_category_code, control_budget_detail_code, period, SUM(amount) AS amount
INTO #rounded
FROM (
    SELECT r.release_seq, s.organisation_code, s.sub_segment_code, s.economic_category_code, s.control_budget_detail_code, s.period, s.amount
    FROM stg.inyear_snapshot AS s JOIN stg.release AS r ON r.release = s.release
    UNION ALL
    SELECT n.release_seq, s.organisation_code, s.sub_segment_code, s.economic_category_code, s.control_budget_detail_code, s.period, -s.amount
    FROM stg.inyear_snapshot AS s
    JOIN stg.release AS r ON r.release = s.release
    JOIN stg.release AS n ON n.release_seq = r.release_seq + 1 AND n.financial_year = r.financial_year
) AS u
GROUP BY release_seq, organisation_code, sub_segment_code, economic_category_code, control_budget_detail_code, period;
GO

SELECT release_seq, COUNT_BIG(*) AS rounded_code_rows
INTO #rounded_count
FROM #rounded
WHERE amount <> 0
GROUP BY release_seq;
GO

-- lines present in two consecutive releases of one year whose organisation key differs
SELECT n.release_seq,
       SUM(CASE WHEN b.amount <> a.amount THEN 1 ELSE 0 END) AS key_change_lines_changed,
       SUM(CASE WHEN b.amount = a.amount THEN 1 ELSE 0 END) AS key_change_lines_same
INTO #keychange
FROM stg.inyear_snapshot AS a
JOIN stg.release AS r ON r.release = a.release
JOIN stg.release AS n ON n.release_seq = r.release_seq + 1 AND n.financial_year = r.financial_year
JOIN stg.inyear_snapshot AS b
  ON b.release = n.release AND b.organisation_code = a.organisation_code AND b.sub_segment_code = a.sub_segment_code
 AND b.economic_category_code = a.economic_category_code AND b.control_budget_detail_code = a.control_budget_detail_code
 AND b.period = a.period
JOIN dw.organisation_release_map AS ma ON ma.release = a.release AND ma.organisation_code = a.organisation_code
JOIN dw.organisation_release_map AS mb ON mb.release = b.release AND mb.organisation_code = b.organisation_code
WHERE ma.organisation_key <> mb.organisation_key AND a.amount <> 0 AND b.amount <> 0
GROUP BY n.release_seq;
GO

SELECT
    CAST(r.label AS varchar(7)) AS release,
    r.release_key,
    CAST(r.financial_year AS varchar(7)) AS financial_year,
    CAST(p.delta_rows_non_zero AS int) AS profile_rows,
    CAST(ISNULL(cs.exact_cs_rows, 0) AS int) AS exact_cs_rows,
    CAST(ISNULL(ec.exact_code_rows, 0) AS int) AS exact_code_rows,
    CAST(ISNULL(rc.rounded_code_rows, 0) AS int) AS rounded_code_rows,
    CAST(ISNULL(fc.fact_rows, 0) AS int) AS fact_rows,
    CAST(ISNULL(cs.exact_cs_rows, 0) - CAST(p.delta_rows_non_zero AS int) AS int) AS profile_diff_rows,
    CAST(ISNULL(ec.exact_code_rows, 0) - ISNULL(cs.exact_cs_rows, 0) AS int) AS case_rows,
    CAST(ISNULL(rc.rounded_code_rows, 0) - ISNULL(ec.exact_code_rows, 0) AS int) AS rounding_rows,
    CAST(ISNULL(fc.fact_rows, 0) - ISNULL(rc.rounded_code_rows, 0) AS int) AS key_rows,
    CAST(ISNULL(k.key_change_lines_changed, 0) AS int) AS key_change_lines_changed,
    CAST(ISNULL(k.key_change_lines_same, 0) AS int) AS key_change_lines_same,
    CAST(ISNULL(fc.fact_rows, 0) - ISNULL(rc.rounded_code_rows, 0)
         - (ISNULL(k.key_change_lines_changed, 0) + 2 * ISNULL(k.key_change_lines_same, 0)) AS int) AS unexplained_rows,
    CAST(CASE
        WHEN ISNULL(fc.fact_rows, 0) = CAST(p.delta_rows_non_zero AS int) THEN 'equal to the profile'
        ELSE 'differs from the profile:'
             + CASE WHEN ISNULL(ec.exact_code_rows, 0) <> ISNULL(cs.exact_cs_rows, 0)
                    THEN ' ' + CAST(ISNULL(cs.exact_cs_rows, 0) - ISNULL(ec.exact_code_rows, 0) AS varchar(20))
                         + ' rows where a sub-segment code changes only in letter case and is one line here;' ELSE '' END
             + CASE WHEN ISNULL(rc.rounded_code_rows, 0) <> ISNULL(ec.exact_code_rows, 0)
                    THEN ' ' + CAST(ISNULL(ec.exact_code_rows, 0) - ISNULL(rc.rounded_code_rows, 0) AS varchar(20))
                         + ' rows where an exact change under 0.0001 rounds to a zero delta;' ELSE '' END
             + CASE WHEN ISNULL(fc.fact_rows, 0) <> ISNULL(rc.rounded_code_rows, 0)
                    THEN ' +' + CAST(ISNULL(fc.fact_rows, 0) - ISNULL(rc.rounded_code_rows, 0) AS varchar(20))
                         + ' rows where an organisation key changes inside the financial year (minus under the old key, plus under the new);' ELSE '' END
        END AS varchar(300)) AS reason
INTO audit.delta_rowcount
FROM dw.dim_release AS r
JOIN raw.profile_inyear_delta_rowcount AS p ON p.release = r.label
LEFT JOIN #exact_count AS ec ON ec.release_seq = r.release_seq
LEFT JOIN #exact_cs_count AS cs ON cs.release_seq = r.release_seq
LEFT JOIN #rounded_count AS rc ON rc.release_seq = r.release_seq
LEFT JOIN (SELECT release_key, COUNT_BIG(*) AS fact_rows FROM dw.fact_outturn GROUP BY release_key) AS fc ON fc.release_key = r.release_key
LEFT JOIN #keychange AS k ON k.release_seq = r.release_seq;
GO

ALTER TABLE audit.delta_rowcount ALTER COLUMN release_key int NOT NULL;
GO
ALTER TABLE audit.delta_rowcount ADD CONSTRAINT pk_audit_delta_rowcount PRIMARY KEY (release_key);
GO

DROP TABLE IF EXISTS #exact;
DROP TABLE IF EXISTS #exact_count;
DROP TABLE IF EXISTS #exact_cs;
DROP TABLE IF EXISTS #exact_cs_count;
DROP TABLE IF EXISTS #rounded;
DROP TABLE IF EXISTS #rounded_count;
DROP TABLE IF EXISTS #keychange;
GO
