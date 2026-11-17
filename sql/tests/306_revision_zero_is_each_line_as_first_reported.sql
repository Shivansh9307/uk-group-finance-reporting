-- test: revision_no 0 rows are exactly the lines ever reported, each with its first reported value; revision numbers run 0, 1, 2 ... in release order
WITH snap AS (
    SELECT r.release_seq, m.organisation_key, sg.segment_key, ac.account_key, cb.control_budget_key,
           CAST(LEFT(s.financial_year, 4) AS int) * 100 + s.period AS period_key, SUM(s.amount) AS amount
    FROM stg.inyear_snapshot AS s
    JOIN stg.release AS r ON r.release = s.release
    JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
    JOIN dw.dim_segment AS sg ON sg.sub_segment_code = s.sub_segment_code
    JOIN dw.dim_account AS ac ON ac.economic_category_code = CASE WHEN s.economic_category_code = 'n/a' THEN 'NA' ELSE s.economic_category_code END
    JOIN dw.dim_control_budget AS cb ON cb.control_budget_detail_code = s.control_budget_detail_code
    GROUP BY r.release_seq, m.organisation_key, sg.segment_key, ac.account_key, cb.control_budget_key,
             CAST(LEFT(s.financial_year, 4) AS int) * 100 + s.period
    HAVING SUM(s.amount) <> 0
), first_seen AS (
    SELECT s.organisation_key, s.segment_key, s.account_key, s.control_budget_key, s.period_key,
           MIN(s.release_seq) AS first_release_seq
    FROM snap AS s
    GROUP BY s.organisation_key, s.segment_key, s.account_key, s.control_budget_key, s.period_key
), first_value AS (
    SELECT fs.organisation_key, fs.segment_key, fs.account_key, fs.control_budget_key, fs.period_key,
           fs.first_release_seq, s.amount AS first_amount
    FROM first_seen AS fs
    JOIN snap AS s
      ON s.release_seq = fs.first_release_seq AND s.organisation_key = fs.organisation_key AND s.segment_key = fs.segment_key
     AND s.account_key = fs.account_key AND s.control_budget_key = fs.control_budget_key AND s.period_key = fs.period_key
), rev0 AS (
    SELECT f.organisation_key, f.segment_key, f.account_key, f.control_budget_key, f.period_key, f.release_key, f.amount_delta
    FROM dw.fact_outturn AS f WHERE f.revision_no = 0
)
SELECT COALESCE(v.organisation_key, r.organisation_key) AS organisation_key, COALESCE(v.segment_key, r.segment_key) AS segment_key,
       COALESCE(v.account_key, r.account_key) AS account_key, COALESCE(v.control_budget_key, r.control_budget_key) AS control_budget_key,
       COALESCE(v.period_key, r.period_key) AS period_key,
       v.first_release_seq, v.first_amount, r.release_key AS revision0_release, r.amount_delta AS revision0_amount,
       'revision 0 differs from the first reported value, or a line has no revision 0, or a revision 0 has no line' AS problem
FROM first_value AS v
FULL OUTER JOIN rev0 AS r
  ON r.organisation_key = v.organisation_key AND r.segment_key = v.segment_key AND r.account_key = v.account_key
 AND r.control_budget_key = v.control_budget_key AND r.period_key = v.period_key
WHERE v.organisation_key IS NULL OR r.organisation_key IS NULL
   OR r.release_key <> v.first_release_seq OR r.amount_delta <> v.first_amount
UNION ALL
SELECT g.organisation_key, g.segment_key, g.account_key, g.control_budget_key, g.period_key, NULL, NULL, NULL, NULL,
       'revision numbers are not 0, 1, 2 ... in release order'
FROM (
    SELECT f.organisation_key, f.segment_key, f.account_key, f.control_budget_key, f.period_key,
           COUNT(*) AS n, MIN(f.revision_no) AS min_rev, MAX(f.revision_no) AS max_rev, COUNT(DISTINCT f.revision_no) AS distinct_rev
    FROM dw.fact_outturn AS f
    GROUP BY f.organisation_key, f.segment_key, f.account_key, f.control_budget_key, f.period_key
) AS g
WHERE g.min_rev <> 0 OR g.max_rev <> g.n - 1 OR g.distinct_rev <> g.n
UNION ALL
SELECT f.organisation_key, f.segment_key, f.account_key, f.control_budget_key, f.period_key, f.release_key, NULL, NULL, NULL,
       'revision number does not rise with the release'
FROM dw.fact_outturn AS f
JOIN dw.fact_outturn AS g
  ON g.organisation_key = f.organisation_key AND g.segment_key = f.segment_key AND g.account_key = f.account_key
 AND g.control_budget_key = f.control_budget_key AND g.period_key = f.period_key
 AND g.revision_no = f.revision_no + 1
WHERE g.release_key <= f.release_key;
