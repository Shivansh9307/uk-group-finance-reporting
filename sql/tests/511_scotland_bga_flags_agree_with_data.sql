-- test: the Scotland block grant adjustment flag of each Estimates workbook agrees with the figures: a gross_of_bga line is within 10 percent of a PESA Scotland figure for the same year on the excluding-depreciation basis; a net_of_bga line is at least 15 percent below those figures, or (2026-27, no PESA gross figure) carries the adjustment as a memo line
WITH scot AS (
    SELECT l.edition, l.plan_source_code, l.year_label, SUM(l.amount_k) AS amount_k
    FROM stg.plan_estimates_line AS l
    WHERE l.target_name = 'Scotland' AND l.row_kind = 'line' AND l.measure = 'RDEL_EX_DEPN' AND l.status_label = 'plans'
    GROUP BY l.edition, l.plan_source_code, l.year_label
),
ref AS (
    SELECT p.year_label, p.amount_k
    FROM stg.plan_pesa_line AS p
    WHERE p.target_name = 'Scotland' AND p.row_kind = 'line' AND p.measure = 'RDEL_EX_DEPN' AND p.edition <> '2026'
)
SELECT s.edition, s.year_label, s.amount_k, d.scotland_bga_flag, 'gross_of_bga line is not within 10 percent of any PESA figure for the year' AS problem
FROM scot AS s JOIN dw.dim_plan_source AS d ON d.plan_source_code = s.plan_source_code
WHERE d.scotland_bga_flag = 'gross_of_bga'
  AND NOT EXISTS (SELECT 1 FROM ref AS r WHERE r.year_label = s.year_label AND ABS(s.amount_k - r.amount_k) <= 0.10 * r.amount_k)
UNION ALL
SELECT s.edition, s.year_label, s.amount_k, d.scotland_bga_flag, 'net_of_bga line is not 15 percent below the PESA figures for the year'
FROM scot AS s JOIN dw.dim_plan_source AS d ON d.plan_source_code = s.plan_source_code
WHERE d.scotland_bga_flag = 'net_of_bga'
  AND EXISTS (SELECT 1 FROM ref AS r WHERE r.year_label = s.year_label AND s.amount_k > 0.85 * r.amount_k)
UNION ALL
SELECT s.edition, s.year_label, s.amount_k, d.scotland_bga_flag, 'net_of_bga line without a PESA figure and without a block grant adjustment memo line'
FROM scot AS s JOIN dw.dim_plan_source AS d ON d.plan_source_code = s.plan_source_code
WHERE d.scotland_bga_flag = 'net_of_bga'
  AND NOT EXISTS (SELECT 1 FROM ref AS r WHERE r.year_label = s.year_label)
  AND NOT EXISTS (SELECT 1 FROM raw.plan_estimates AS e JOIN raw.plan_source_file AS f ON f.file_id = e.file_id
                  WHERE f.edition = s.edition AND LOWER(e.row_label) LIKE '%block grant adjustment%' AND e.row_kind = 'memo')
UNION ALL
SELECT d.plan_source_code, NULL, NULL, d.scotland_bga_flag, 'Estimates source without a Scotland line'
FROM dw.dim_plan_source AS d
WHERE d.family = 'estimates' AND NOT EXISTS (SELECT 1 FROM scot AS s WHERE s.plan_source_code = d.plan_source_code);
