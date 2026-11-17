-- test: for every release R, the deltas up to R for R's financial year equal R's snapshot on every line, and are zero for every line R does not report
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
), asat AS (
    SELECT r.release_seq, f.organisation_key, f.segment_key, f.account_key, f.control_budget_key, f.period_key,
           SUM(f.amount_delta) AS amount
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS p ON p.period_key = f.period_key
    JOIN dw.dim_release AS r ON r.financial_year = p.financial_year AND r.release_key >= f.release_key
    GROUP BY r.release_seq, f.organisation_key, f.segment_key, f.account_key, f.control_budget_key, f.period_key
    HAVING SUM(f.amount_delta) <> 0
)
SELECT COALESCE(a.release_seq, s.release_seq) AS release_seq,
       COALESCE(a.organisation_key, s.organisation_key) AS organisation_key,
       COALESCE(a.segment_key, s.segment_key) AS segment_key,
       COALESCE(a.account_key, s.account_key) AS account_key,
       COALESCE(a.control_budget_key, s.control_budget_key) AS control_budget_key,
       COALESCE(a.period_key, s.period_key) AS period_key,
       a.amount AS as_at_from_deltas, s.amount AS reported
FROM asat AS a
FULL OUTER JOIN snap AS s
  ON s.release_seq = a.release_seq AND s.organisation_key = a.organisation_key AND s.segment_key = a.segment_key
 AND s.account_key = a.account_key AND s.control_budget_key = a.control_budget_key AND s.period_key = a.period_key
WHERE ISNULL(a.amount, 0) <> ISNULL(s.amount, 0);
