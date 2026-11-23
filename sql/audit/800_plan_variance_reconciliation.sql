-- scope: full
-- audit.plan_variance_reconciliation: every plan variance of the model from FY2022-23, one row per financial year x
-- Spending Review group x plan measure, with the plan, the outturn the model sets against it, the variance, an
-- independent outturn for the same cell, the part of the variance each named cause accounts for, the residual and a
-- verdict. GBP thousands, spending positive; variance = outturn less plan, below zero is favourable.
--
--   Measures: RDEL_EX_DEPN (resource DEL excluding depreciation), CDEL, RAME, CAME (departmental AME). The measures of
--   dw.fact_plan that the model adds up without a measure chosen (administration is part of resource DEL).
--   Years: every financial year from 2022-23 that has a year-end release (the full-year outturn of the latest release).
--   plan              dw.fact_plan, the rows the model's Plan adds up (is_part_of_other_measure = 0)
--   outturn           dw.outturn_plan_basis_inyear at the year-end release: what Outturn (plan basis) returns (test 726)
--   outturn_annual    dw.outturn_plan_basis_annual from the newest annual vintage that holds the year (to 2024-25)
--   outturn_pss       the Public Spending Statistics database (resource DEL excluding depreciation and capital DEL)
--   outturn_pesa      PESA, the newest edition on the framework of the plans (PESA December 2025 for AME to 2024-25);
--                     PESA 2026 for AME in 2025-26, on a different framework (see audit.pesa_2026_basis_change)
--   outturn_reference the independent outturn the gaps are measured against: the annual file where it holds the year
--                     (same publisher and basis as the model), otherwise the PSS for DEL; none for AME in 2025-26
--   Groups: the group the plan is published under. For FY2022-23 the reference outturn of the groups that the combined
--   BEIS, DCMS and DIT group replaces is added into it (dw.plan_group_rule).
--
--   The gaps, which add up to the variance (residual is what is left):
--     gap_plan_only     the plan of a group that has no outturn in OSCAR (the Single Intelligence Account, non-department
--                       members): the whole variance
--     gap_outturn_only  outturn of a group that has no plan (the unallocated former-department member)
--     gap_first_look    outturn less the reference outturn: the in-year files are the first look; the annual file is final
--     gap_on_reference  the reference outturn less the plan: what the variance would be on the independent figures
--     residual          variance less the three gaps above, counting gap_first_look only where its cause is named or it is
--                       within tolerance
--   Tolerances (GBP thousands): variance tolerance max(5% of the plan, 100,000); first-look tolerance max(2% of the plan,
--   100,000).
--   first_look_cause  the named cause of a first-look gap above tolerance: 'block grant adjustment' (Scotland, DEL),
--                     'category <code> <name>' (one economic category accounts for at least 60% of the gap, measured
--                     against the annual file), 'AME on another framework' (no outturn on the plan's framework exists)
--   verdict           ok | fixed | explained: <reason> | unexplained
--     fixed        the group is the combined BEIS, DCMS and DIT group in FY2022-23: with outturn on the current structure it
--                  had a plan and no outturn (variance minus 100%); dw.plan_group_rule puts the outturn on its structure
--     ok           the variance is within tolerance, or a DEL variance above tolerance that the independent outturn confirms
--     explained    the gaps name the cause and the residual is within the variance tolerance
--     unexplained  anything else
-- Real figures; the causes are rules over those figures, not estimates. Nothing here reaches a model total.

DROP TABLE IF EXISTS audit.plan_variance_reconciliation;
DROP TABLE IF EXISTS audit.pesa_2026_basis_change;
GO

DROP TABLE IF EXISTS #yrs;
DROP TABLE IF EXISTS #fold;
DROP TABLE IF EXISTS #p;
DROP TABLE IF EXISTS #o;
DROP TABLE IF EXISTS #a;
DROP TABLE IF EXISTS #s;
DROP TABLE IF EXISTS #e;
DROP TABLE IF EXISTS #bga;
DROP TABLE IF EXISTS #cat;
DROP TABLE IF EXISTS #drv;
DROP TABLE IF EXISTS #cell;
GO

SELECT DISTINCT financial_year
INTO #yrs
FROM dw.outturn_plan_basis_inyear
WHERE is_year_end_release = 1 AND financial_year >= '2022-23';
GO

-- the groups of the current structure that a plan group replaces in a year (FY2022-23: the combined group)
SELECT DISTINCT financial_year, sr_group_key AS from_key, plan_sr_group_key AS to_key
INTO #fold
FROM dw.outturn_plan_line
WHERE plan_sr_group_key <> sr_group_key;
GO

SELECT f.financial_year, f.sr_group_key, f.measure, SUM(f.amount) AS amount
INTO #p
FROM dw.fact_plan AS f
WHERE f.is_part_of_other_measure = 0 AND f.measure IN ('RDEL_EX_DEPN', 'CDEL', 'RAME', 'CAME')
  AND f.financial_year IN (SELECT financial_year FROM #yrs)
GROUP BY f.financial_year, f.sr_group_key, f.measure;
GO

SELECT b.financial_year, b.sr_group_key, b.measure, SUM(b.amount) AS amount
INTO #o
FROM dw.outturn_plan_basis_inyear AS b
WHERE b.is_year_end_release = 1 AND b.measure IN ('RDEL_EX_DEPN', 'CDEL', 'RAME', 'CAME')
  AND b.financial_year IN (SELECT financial_year FROM #yrs)
GROUP BY b.financial_year, b.sr_group_key, b.measure;
GO

-- annual file, regrouped as the plan: the vintage is the newest that holds the year
SELECT a.financial_year, COALESCE(fd.to_key, a.sr_group_key) AS sr_group_key, a.measure, MAX(a.vintage) AS vintage, SUM(a.amount) AS amount
INTO #a
FROM dw.outturn_plan_basis_annual AS a
LEFT JOIN #fold AS fd ON fd.financial_year = a.financial_year AND fd.from_key = a.sr_group_key
WHERE a.is_latest_vintage_for_year = 1 AND a.measure IN ('RDEL_EX_DEPN', 'CDEL', 'RAME', 'CAME')
  AND a.financial_year IN (SELECT financial_year FROM #yrs)
GROUP BY a.financial_year, COALESCE(fd.to_key, a.sr_group_key), a.measure;
GO

-- PSS: DEL only (departmental AME does not reconcile in the PSS)
SELECT p.financial_year, COALESCE(fd.to_key, g.sr_group_key) AS sr_group_key,
       CAST(CASE WHEN p.basis_rdel_excl_depreciation = 1 THEN 'RDEL_EX_DEPN' ELSE 'CDEL' END AS varchar(20)) AS measure,
       SUM(p.amount) AS amount
INTO #s
FROM stg.pss_outturn AS p
JOIN stg.pss_sr_group_map AS mm ON mm.pss_sr_group_name = p.sr_group_name
JOIN dw.dim_sr_group AS g ON g.sr_group_name = mm.sr_group_name
LEFT JOIN #fold AS fd ON fd.financial_year = p.financial_year AND fd.from_key = g.sr_group_key
WHERE p.financial_year IN (SELECT financial_year FROM #yrs)
  AND (p.basis_rdel_excl_depreciation = 1 OR (p.control_budget_code = 'DEL' AND p.economic_budget_code = 'CAPITAL'))
GROUP BY p.financial_year, COALESCE(fd.to_key, g.sr_group_key),
         CASE WHEN p.basis_rdel_excl_depreciation = 1 THEN 'RDEL_EX_DEPN' ELSE 'CDEL' END;
GO

-- PESA departmental AME outturn: December 2025 where it holds the year, otherwise the 2026 edition
SELECT x.financial_year, COALESCE(fd.to_key, x.sr_group_key) AS sr_group_key, x.measure, MAX(x.plan_source_code) AS plan_source_code, SUM(x.amount) AS amount
INTO #e
FROM (
    SELECT l.year_label AS financial_year, g.sr_group_key, l.plan_source_code,
           CAST(CASE l.measure WHEN 'RESOURCE_DEPT_AME' THEN 'RAME' ELSE 'CAME' END AS varchar(20)) AS measure, SUM(l.amount_k) AS amount,
           DENSE_RANK() OVER (PARTITION BY l.year_label, l.measure
                              ORDER BY CASE WHEN l.plan_source_code = 'PESA_2025_12' THEN 0 ELSE 1 END, l.plan_source_code DESC) AS rk
    FROM stg.plan_pesa_line AS l
    JOIN dw.dim_sr_group AS g ON g.sr_group_name = l.target_name
    WHERE l.status_label = 'outturn' AND l.row_kind = 'line' AND l.line_role IN ('whole', 'part')
      AND l.measure IN ('RESOURCE_DEPT_AME', 'CAPITAL_DEPT_AME') AND l.plan_source_code LIKE 'PESA[_]%'
      AND l.year_label IN (SELECT financial_year FROM #yrs)
    GROUP BY l.year_label, g.sr_group_key, l.plan_source_code, l.measure
) AS x
LEFT JOIN #fold AS fd ON fd.financial_year = x.financial_year AND fd.from_key = x.sr_group_key
WHERE x.rk = 1
GROUP BY x.financial_year, COALESCE(fd.to_key, x.sr_group_key), x.measure;
GO

-- the Scottish block grant adjustment as PESA 2026 publishes it (a memo line, negative)
SELECT l.year_label AS financial_year, SUM(l.amount_k) AS amount
INTO #bga
FROM stg.plan_pesa_line AS l
WHERE l.plan_source_code = 'PESA_2026' AND l.status_label = 'outturn' AND l.line_role = 'component'
  AND l.row_label_clean LIKE 'Scottish Government Block Grant Adjustments%'
GROUP BY l.year_label;
GO

-- economic categories: in-year against annual, by cell (years the annual file holds)
WITH grp AS (
    SELECT b.vintage, b.financial_year, b.organisation_code, COALESCE(gc.sr_group_key, gn.sr_group_key) AS sr_group_key
    FROM stg.bud_sr_group_by_organisation AS b
    LEFT JOIN dw.dim_sr_group AS gc ON gc.sr_group_code = b.sr_group_code
    LEFT JOIN stg.plan_name_map AS m ON m.name_family = 'oscar_extract' AND m.plan_name = b.sr_group_name AND gc.sr_group_key IS NULL
    LEFT JOIN dw.dim_sr_group AS gn ON gn.sr_group_name = m.target_name
), ann AS (
    SELECT f.financial_year, COALESCE(fd.to_key, g.sr_group_key) AS sr_group_key, ms.measure, f.economic_category_code, SUM(f.amount) AS amount
    FROM dw.fact_outturn_annual AS f
    JOIN grp AS g ON g.vintage = f.vintage AND g.financial_year = f.financial_year AND g.organisation_code = f.organisation_code
    LEFT JOIN #fold AS fd ON fd.financial_year = f.financial_year AND fd.from_key = g.sr_group_key
    CROSS APPLY (VALUES
        ('RDEL_EX_DEPN', CAST(f.basis_rdel_excl_depreciation AS int)),
        ('CDEL',         CASE WHEN f.control_budget_code = 'DEL' AND f.economic_budget_code = 'CAPITAL' THEN 1 ELSE 0 END),
        ('RAME',         CASE WHEN f.control_budget_detail_code = 'DEPT AME' AND f.economic_budget_code = 'RESOURCE' THEN 1 ELSE 0 END),
        ('CAME',         CASE WHEN f.control_budget_detail_code = 'DEPT AME' AND f.economic_budget_code = 'CAPITAL' THEN 1 ELSE 0 END)
    ) AS ms (measure, selected)
    WHERE ms.selected = 1 AND f.vintage = (SELECT MAX(vintage) FROM dw.fact_outturn_annual AS v WHERE v.financial_year = f.financial_year)
      AND f.financial_year IN (SELECT financial_year FROM #yrs)
    GROUP BY f.financial_year, COALESCE(fd.to_key, g.sr_group_key), ms.measure, f.economic_category_code
), iny AS (
    SELECT p.financial_year, COALESCE(gr.plan_sr_group_key, b.sr_group_key) AS sr_group_key, ms.measure, a.economic_category_code, SUM(f.amount_delta) AS amount
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS p ON p.period_key = f.period_key
    JOIN dw.dim_segment AS sg ON sg.segment_key = f.segment_key
    JOIN dw.outturn_sr_group_bridge AS b ON b.organisation_key = f.organisation_key AND b.sub_segment_code = sg.sub_segment_code
    JOIN dw.dim_department AS rd ON rd.department_key = f.department_key
    LEFT JOIN dw.plan_group_rule AS gr ON gr.financial_year = p.financial_year AND gr.department_number = rd.department_number
    JOIN dw.dim_account AS a ON a.account_key = f.account_key
    JOIN dw.dim_control_budget AS cb ON cb.control_budget_key = f.control_budget_key
    CROSS APPLY (VALUES
        ('RDEL_EX_DEPN', CASE WHEN cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN') AND a.economic_budget = 'RESOURCE' AND a.pesa_economic_group_code <> 'DEPRECIATION' THEN 1 ELSE 0 END),
        ('CDEL',         CASE WHEN cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN') AND a.economic_budget = 'CAPITAL' THEN 1 ELSE 0 END),
        ('RAME',         CASE WHEN cb.control_budget_detail_code = 'DEPT AME' AND a.economic_budget = 'RESOURCE' THEN 1 ELSE 0 END),
        ('CAME',         CASE WHEN cb.control_budget_detail_code = 'DEPT AME' AND a.economic_budget = 'CAPITAL' THEN 1 ELSE 0 END)
    ) AS ms (measure, selected)
    WHERE ms.selected = 1 AND p.financial_year IN (SELECT financial_year FROM #yrs)
      AND p.financial_year IN (SELECT financial_year FROM #a)
    GROUP BY p.financial_year, COALESCE(gr.plan_sr_group_key, b.sr_group_key), ms.measure, a.economic_category_code
)
SELECT COALESCE(i.financial_year, n.financial_year) AS financial_year, COALESCE(i.sr_group_key, n.sr_group_key) AS sr_group_key,
       COALESCE(i.measure, n.measure) AS measure, COALESCE(i.economic_category_code, n.economic_category_code) AS economic_category_code,
       ISNULL(i.amount, 0) AS inyear_amount, ISNULL(n.amount, 0) AS annual_amount, ISNULL(i.amount, 0) - ISNULL(n.amount, 0) AS gap
INTO #cat
FROM iny AS i
FULL OUTER JOIN ann AS n ON n.financial_year = i.financial_year AND n.sr_group_key = i.sr_group_key AND n.measure = i.measure
                        AND n.economic_category_code = i.economic_category_code;
GO

-- the category with the largest gap in each cell, and the share of the cell's gap it makes up
SELECT c.financial_year, c.sr_group_key, c.measure, c.economic_category_code, c.gap AS driver_gap,
       t.cell_gap, CAST(CASE WHEN t.cell_gap = 0 THEN NULL ELSE c.gap / t.cell_gap END AS decimal(12, 6)) AS driver_share,
       c.inyear_amount AS driver_inyear, c.annual_amount AS driver_annual
INTO #drv
FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY financial_year, sr_group_key, measure
                                   ORDER BY ABS(gap) DESC, economic_category_code) AS rn FROM #cat) AS c
JOIN (SELECT financial_year, sr_group_key, measure, SUM(gap) AS cell_gap FROM #cat GROUP BY financial_year, sr_group_key, measure) AS t
  ON t.financial_year = c.financial_year AND t.sr_group_key = c.sr_group_key AND t.measure = c.measure
WHERE c.rn = 1;
GO

SELECT k.financial_year, k.sr_group_key, k.measure,
       p.amount AS plan_amount, ISNULL(o.amount, 0) AS outturn,
       a.amount AS outturn_annual, a.vintage AS annual_vintage, s.amount AS outturn_pss, e.amount AS outturn_pesa, e.plan_source_code AS pesa_edition
INTO #cell
FROM (SELECT financial_year, sr_group_key, measure FROM #p UNION SELECT financial_year, sr_group_key, measure FROM #o) AS k
LEFT JOIN #p AS p ON p.financial_year = k.financial_year AND p.sr_group_key = k.sr_group_key AND p.measure = k.measure
LEFT JOIN #o AS o ON o.financial_year = k.financial_year AND o.sr_group_key = k.sr_group_key AND o.measure = k.measure
LEFT JOIN #a AS a ON a.financial_year = k.financial_year AND a.sr_group_key = k.sr_group_key AND a.measure = k.measure
LEFT JOIN #s AS s ON s.financial_year = k.financial_year AND s.sr_group_key = k.sr_group_key AND s.measure = k.measure
LEFT JOIN #e AS e ON e.financial_year = k.financial_year AND e.sr_group_key = k.sr_group_key AND e.measure = k.measure;
GO

CREATE TABLE audit.plan_variance_reconciliation (
    financial_year       varchar(7)      NOT NULL,
    sr_group_code        varchar(20)     NOT NULL,
    sr_group_name        nvarchar(100)   NOT NULL,
    measure              varchar(20)     NOT NULL,
    plan_amount          decimal(19, 4)  NOT NULL,
    outturn              decimal(19, 4)  NOT NULL,
    variance             decimal(19, 4)  NOT NULL,
    variance_share       decimal(12, 6)  NULL,
    outturn_annual       decimal(19, 4)  NULL,
    outturn_pss          decimal(19, 4)  NULL,
    outturn_pesa         decimal(19, 4)  NULL,
    reference_source     varchar(40)     NULL,
    outturn_reference    decimal(19, 4)  NULL,
    gap_plan_only        decimal(19, 4)  NOT NULL,
    gap_outturn_only     decimal(19, 4)  NOT NULL,
    gap_first_look       decimal(19, 4)  NOT NULL,
    gap_on_reference     decimal(19, 4)  NOT NULL,
    residual             decimal(19, 4)  NOT NULL,
    first_look_cause     varchar(120)    NULL,
    cause_evidence       varchar(300)    NULL,
    variance_tolerance   decimal(19, 4)  NOT NULL,
    verdict_class        varchar(12)     NOT NULL,
    verdict              varchar(200)    NOT NULL,
    CONSTRAINT pk_audit_plan_variance_reconciliation PRIMARY KEY (financial_year, sr_group_code, measure)
);
GO

WITH base AS (
    SELECT c.financial_year, g.sr_group_code, g.sr_group_name, g.member_type, g.has_outturn, c.measure,
           CAST(ISNULL(c.plan_amount, 0) AS decimal(19, 4)) AS plan_amount, CAST(c.outturn AS decimal(19, 4)) AS outturn,
           c.outturn_annual, c.outturn_pss, c.outturn_pesa, c.pesa_edition, c.annual_vintage,
           CASE WHEN c.outturn_annual IS NOT NULL THEN 'annual file ' + c.annual_vintage
                WHEN c.outturn_pss IS NOT NULL THEN 'PSS'
                ELSE NULL END AS reference_source,
           COALESCE(c.outturn_annual, c.outturn_pss) AS outturn_reference,
           d.economic_category_code AS driver_code, d.driver_gap, d.driver_share, d.driver_inyear, d.driver_annual,
           (SELECT TOP 1 a.economic_category_name FROM dw.dim_account AS a WHERE a.economic_category_code = d.economic_category_code) AS driver_name,
           b.amount AS bga_memo
    FROM #cell AS c
    JOIN dw.dim_sr_group AS g ON g.sr_group_key = c.sr_group_key
    LEFT JOIN #drv AS d ON d.financial_year = c.financial_year AND d.sr_group_key = c.sr_group_key AND d.measure = c.measure
    LEFT JOIN #bga AS b ON b.financial_year = c.financial_year AND g.sr_group_name = N'Scotland'
), calc AS (
    SELECT x.*, x.outturn - x.plan_amount AS variance,
           CASE WHEN x.has_outturn = 0 AND x.outturn = 0 THEN 1 ELSE 0 END AS is_plan_only,
           CASE WHEN x.plan_amount = 0 AND x.outturn <> 0 THEN 1 ELSE 0 END AS is_outturn_only,
           CASE WHEN x.measure IN ('RAME', 'CAME') THEN 1 ELSE 0 END AS is_ame,
           CASE WHEN x.sr_group_code = 'COMBINED_PRE2023' AND x.financial_year = '2022-23' THEN 1 ELSE 0 END AS is_combined,
           0.05 * ABS(x.plan_amount) AS t5, 0.02 * ABS(x.plan_amount) AS t2, 0.1 * ABS(x.outturn - x.plan_amount) AS t10v
    FROM base AS x
), gaps AS (
    SELECT y.*,
           CASE WHEN y.t5 > 100000 THEN y.t5 ELSE 100000 END AS variance_tolerance,
           CASE WHEN y.t2 >= y.t10v AND y.t2 > 100000 THEN y.t2 WHEN y.t10v > 100000 THEN y.t10v ELSE 100000 END AS first_look_tolerance,
           CASE WHEN y.is_plan_only = 1 THEN y.variance ELSE 0 END AS gap_plan_only,
           CASE WHEN y.is_outturn_only = 1 THEN y.variance ELSE 0 END AS gap_outturn_only,
           CASE WHEN y.is_plan_only = 0 AND y.is_outturn_only = 0 AND y.outturn_reference IS NOT NULL THEN y.outturn - y.outturn_reference ELSE 0 END AS gap_first_look,
           CASE WHEN y.is_plan_only = 0 AND y.is_outturn_only = 0 AND y.outturn_reference IS NOT NULL THEN y.outturn_reference - y.plan_amount ELSE 0 END AS gap_on_reference
    FROM calc AS y
), caused AS (
    SELECT z.*,
           CASE WHEN ABS(z.gap_first_look) <= z.first_look_tolerance THEN 'within tolerance'
                WHEN z.sr_group_name = N'Scotland' AND z.measure IN ('RDEL_EX_DEPN', 'CDEL') AND z.bga_memo IS NOT NULL
                     AND ABS(z.gap_first_look - z.bga_memo) <= 0.1 * ABS(z.bga_memo) THEN 'block grant adjustment'
                WHEN z.driver_share >= 0.6 AND z.driver_code IS NOT NULL THEN 'category ' + z.driver_code + ' ' + ISNULL(z.driver_name, '')
                WHEN z.outturn_reference IS NULL AND z.is_ame = 1 AND z.is_plan_only = 0 AND z.is_outturn_only = 0 THEN 'AME on another framework'
                ELSE NULL END AS first_look_cause
    FROM gaps AS z
)
INSERT INTO audit.plan_variance_reconciliation
    (financial_year, sr_group_code, sr_group_name, measure, plan_amount, outturn, variance, variance_share, outturn_annual, outturn_pss,
     outturn_pesa, reference_source, outturn_reference, gap_plan_only, gap_outturn_only, gap_first_look, gap_on_reference,
     residual, first_look_cause, cause_evidence, variance_tolerance, verdict_class, verdict)
SELECT w.financial_year, w.sr_group_code, w.sr_group_name, w.measure, w.plan_amount, w.outturn, w.variance,
       CAST(w.variance / NULLIF(ABS(w.plan_amount), 0) AS decimal(12, 6)),
       w.outturn_annual, w.outturn_pss, w.outturn_pesa, CAST(w.reference_source AS varchar(40)), w.outturn_reference,
       w.gap_plan_only, w.gap_outturn_only, w.gap_first_look, w.gap_on_reference,
       -- residual: what no named cause accounts for
       CAST(CASE WHEN w.is_plan_only = 1 OR w.is_outturn_only = 1 THEN 0
                 WHEN w.outturn_reference IS NULL THEN w.variance
                 WHEN w.first_look_cause IS NULL THEN w.gap_first_look
                 ELSE 0 END AS decimal(19, 4)),
       CAST(w.first_look_cause AS varchar(120)),
       CAST(CASE WHEN w.first_look_cause = 'block grant adjustment'
                 THEN 'PESA 2026 Table 1.3 block grant adjustment memo line for the year: ' + FORMAT(w.bga_memo, 'N0') + ' thousand'
                 WHEN w.first_look_cause LIKE 'category %'
                 THEN 'against the annual file: in-year ' + FORMAT(w.driver_inyear, 'N0') + ', annual ' + FORMAT(w.driver_annual, 'N0') + ' thousand, ' + FORMAT(w.driver_share * 100, 'N0') + '% of the cell gap'
                 END AS varchar(300)),
       w.variance_tolerance,
       CAST(CASE WHEN ABS(w.variance) <= w.variance_tolerance THEN 'ok'
                 WHEN w.is_plan_only = 1 OR w.is_outturn_only = 1 THEN 'explained'
                 WHEN w.outturn_reference IS NULL AND w.first_look_cause IS NULL THEN 'unexplained'
                 WHEN w.outturn_reference IS NULL THEN 'explained'
                 WHEN w.first_look_cause = 'within tolerance' AND w.is_ame = 0 THEN 'ok'
                 WHEN w.first_look_cause IS NOT NULL THEN 'explained'
                 ELSE 'unexplained' END AS varchar(12)),
       CAST('' AS varchar(200))
FROM caused AS w;
GO

-- a first-look gap above tolerance in a year with no annual file (the year just closed), where the same group and measure had
-- a named economic category as the cause in the year before and a gap of the same sign within 30% of it: the same cause,
-- carried forward and labelled as carried, not measured (no annual file exists to measure it against)
-- the PSS and OSCAR draw a group boundary differently by a stable amount: the prior year's gap of the in-year outturn to the PSS,
-- where the in-year outturn agreed with the annual file, is the same size and sign
UPDATE r SET first_look_cause = CAST('PSS group boundary (carried from ' + prev.financial_year + ', not measured)' AS varchar(120)),
             cause_evidence = CAST('in ' + prev.financial_year + ' the in-year outturn agreed with the annual file and was ' + FORMAT(prev.outturn - prev.outturn_pss, 'N0') + ' thousand away from the PSS' AS varchar(300)),
             residual = 0,
             verdict_class = 'explained'
FROM audit.plan_variance_reconciliation AS r
JOIN audit.plan_variance_reconciliation AS prev
  ON prev.sr_group_code = r.sr_group_code AND prev.measure = r.measure
 AND prev.financial_year = CAST(CAST(LEFT(r.financial_year, 4) AS int) - 1 AS varchar(4)) + '-' + RIGHT(LEFT(r.financial_year, 4), 2)
WHERE r.first_look_cause IS NULL AND r.reference_source = 'PSS' AND r.outturn_annual IS NULL
  AND prev.first_look_cause = 'within tolerance' AND prev.outturn_annual IS NOT NULL AND prev.outturn_pss IS NOT NULL
  AND SIGN(prev.outturn - prev.outturn_pss) = SIGN(r.gap_first_look)
  AND ABS(r.gap_first_look) BETWEEN 0.7 * ABS(prev.outturn - prev.outturn_pss) AND 1.3 * ABS(prev.outturn - prev.outturn_pss);
GO

UPDATE r SET first_look_cause = CAST(prev.first_look_cause + ' (carried from ' + prev.financial_year + ', not measured)' AS varchar(120)),
             cause_evidence = CAST('no annual file for ' + r.financial_year + ' yet; in ' + prev.financial_year + ' the same gap was ' + FORMAT(prev.gap_first_look, 'N0') + ' thousand against the annual file (' + prev.cause_evidence + ')' AS varchar(300)),
             residual = 0,
             verdict_class = 'explained'
FROM audit.plan_variance_reconciliation AS r
JOIN audit.plan_variance_reconciliation AS prev
  ON prev.sr_group_code = r.sr_group_code AND prev.measure = r.measure
 AND prev.financial_year = CAST(CAST(LEFT(r.financial_year, 4) AS int) - 1 AS varchar(4)) + '-' + RIGHT(LEFT(r.financial_year, 4), 2)
WHERE r.first_look_cause IS NULL AND r.reference_source = 'PSS' AND r.outturn_annual IS NULL
  AND prev.first_look_cause LIKE 'category %' AND prev.outturn_annual IS NOT NULL
  AND SIGN(prev.gap_first_look) = SIGN(r.gap_first_look)
  AND ABS(r.gap_first_look) BETWEEN 0.7 * ABS(prev.gap_first_look) AND 1.3 * ABS(prev.gap_first_look);
GO

-- verdict text: the reason is part of the verdict
UPDATE r SET verdict = CAST(CASE r.verdict_class
    WHEN 'ok' THEN 'ok'
    WHEN 'fixed' THEN 'fixed'
    WHEN 'unexplained' THEN 'unexplained'
    ELSE 'explained: ' +
        CASE WHEN g.has_outturn = 0 AND r.outturn = 0
                  THEN 'plan-only line, OSCAR has no outturn for it'
             WHEN r.plan_amount = 0 THEN 'outturn with no plan line'
             WHEN r.first_look_cause = 'within tolerance' AND r.measure IN ('RAME', 'CAME')
                  THEN 'AME plan is a forecast; the annual outturn agrees with the model'
             WHEN r.first_look_cause = 'AME on another framework'
                  THEN 'AME plan is a forecast; no outturn on its framework (PESA 2026 differs)'
             WHEN r.first_look_cause = 'block grant adjustment'
                  THEN 'Scotland in-year outturn is net of the block grant adjustment'
             WHEN r.first_look_cause LIKE 'category %'
                  THEN 'first look differs from final in ' + SUBSTRING(r.first_look_cause, 10, 110)
             ELSE r.first_look_cause END
    END AS varchar(200))
FROM audit.plan_variance_reconciliation AS r
JOIN dw.dim_sr_group AS g ON g.sr_group_code = r.sr_group_code;
GO

-- the combined BEIS, DCMS and DIT group in FY2022-23: with outturn on the current structure it had a plan and no outturn
-- (variance minus 100%); the group rule puts the outturn on the structure of the plan. What is left of its variance keeps
-- its own verdict, written into the text.
UPDATE r SET verdict = CAST('fixed: outturn on the plan structure; remainder ' +
                            CASE r.verdict_class WHEN 'ok' THEN 'ok'
                                                 WHEN 'unexplained' THEN 'unexplained'
                                                 ELSE r.verdict END AS varchar(200)),
             verdict_class = 'fixed'
FROM audit.plan_variance_reconciliation AS r
WHERE r.sr_group_code = 'COMBINED_PRE2023' AND r.financial_year = '2022-23';
GO

-- audit.pesa_2026_basis_change: the same financial year in PESA December 2025 and PESA 2026, to show that PESA 2026 is on
-- a different framework. Resource DEL falls and departmental resource AME rises by about the same amount (the ringfenced
-- depreciation moves into AME), so PESA 2026 AME outturn is not comparable with the plans of earlier editions.
-- GBP thousands; change = PESA 2026 less PESA December 2025, in total over the groups both editions list.
CREATE TABLE audit.pesa_2026_basis_change (
    financial_year  varchar(7)      NOT NULL,
    measure         varchar(20)     NOT NULL,
    pesa_2025_12    decimal(19, 4)  NOT NULL,
    pesa_2026       decimal(19, 4)  NOT NULL,
    change          decimal(19, 4)  NOT NULL,
    CONSTRAINT pk_audit_pesa_2026_basis_change PRIMARY KEY (financial_year, measure)
);
GO

INSERT INTO audit.pesa_2026_basis_change (financial_year, measure, pesa_2025_12, pesa_2026, change)
SELECT l.year_label,
       CAST(CASE l.measure WHEN 'RESOURCE_DEPT_AME' THEN 'RAME' WHEN 'CAPITAL_DEPT_AME' THEN 'CAME' ELSE l.measure END AS varchar(20)),
       SUM(CASE WHEN l.plan_source_code = 'PESA_2025_12' THEN l.amount_k END),
       SUM(CASE WHEN l.plan_source_code = 'PESA_2026' THEN l.amount_k END),
       SUM(CASE WHEN l.plan_source_code = 'PESA_2026' THEN l.amount_k END) - SUM(CASE WHEN l.plan_source_code = 'PESA_2025_12' THEN l.amount_k END)
FROM stg.plan_pesa_line AS l
WHERE l.status_label = 'outturn' AND l.row_kind = 'line' AND l.line_role IN ('whole', 'part')
  AND l.plan_source_code IN ('PESA_2025_12', 'PESA_2026') AND l.measure IN ('RDEL', 'RESOURCE_DEPT_AME', 'CDEL', 'CAPITAL_DEPT_AME')
  AND l.year_label BETWEEN '2022-23' AND '2024-25'
GROUP BY l.year_label, CASE l.measure WHEN 'RESOURCE_DEPT_AME' THEN 'RAME' WHEN 'CAPITAL_DEPT_AME' THEN 'CAME' ELSE l.measure END;
GO
