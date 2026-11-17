-- test: the 2026-27 Main Estimate (a table not titled excluding depreciation) is on the excluding-depreciation basis: each department line equals PESA 2026 Table 1.3 resource DEL for 2026-27 to the nearest GBP million, and the Estimates total equals the PESA total once reserves, the OBR allowance and the Budget Exchange adjustment are taken out
WITH est AS (
    SELECT l.target_name, SUM(l.amount_k) AS amount_k
    FROM stg.plan_estimates_line AS l
    WHERE l.edition = '2026-27-mains' AND l.measure = 'RDEL_EX_DEPN' AND l.row_kind = 'line' AND l.year_label = '2026-27'
    GROUP BY l.target_name
),
pesa AS (
    SELECT p.target_name, SUM(p.amount_k) AS amount_k
    FROM stg.plan_pesa_line AS p
    WHERE p.edition = '2026' AND p.sheet = 'Table_1_3' AND p.measure = 'RDEL' AND p.row_kind = 'line' AND p.year_label = '2026-27'
      AND p.section LIKE 'Resource DEL by departmental group%' AND p.line_role <> 'component'
    GROUP BY p.target_name
)
SELECT COALESCE(e.target_name, p.target_name) AS target_name, e.amount_k AS estimates_k, p.amount_k AS pesa_k, 'department line differs by more than GBP 1m' AS problem
FROM est AS e
FULL OUTER JOIN pesa AS p ON p.target_name = e.target_name
WHERE COALESCE(e.target_name, p.target_name) IN (SELECT sr_group_name FROM dw.dim_sr_group WHERE member_type IN ('spending_review_group', 'plan_only'))
  AND (e.amount_k IS NULL OR p.amount_k IS NULL OR ABS(e.amount_k - p.amount_k) > 1000)
UNION ALL
SELECT 'total', e.t, p.t, 'Estimates total differs from the PESA total less reserves, OBR allowance and Budget Exchange by more than GBP 5m'
FROM (SELECT SUM(amount_k) AS t FROM est) AS e
CROSS JOIN (SELECT SUM(CASE WHEN g.member_type IN ('spending_review_group', 'plan_only') THEN p.amount_k END) AS t FROM pesa AS p
            JOIN dw.dim_sr_group AS g ON g.sr_group_name = p.target_name) AS p
WHERE ABS(e.t - p.t) > 5000;
