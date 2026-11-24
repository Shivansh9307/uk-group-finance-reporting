-- scope: full
-- audit.tac_cash_flow_tie: what the NHS providers' published cash flow statements say about themselves, and how the
-- derived (indirect) cash flow ties to the balance sheet. One row per file year and tie.
--   tie_code                     what is compared (the rows below)
--   provider_years               provider-years in which both sides exist
--   provider_years_breaking_1k   provider-years where the two sides differ by 1 (GBP 1,000) or more
--   max_abs_difference           the largest difference in one provider-year, GBP thousand
--   left_total, right_total      the two sides added over the providers, GBP thousand, TAC sign
-- Nothing is filtered out and nothing is forced: a tie that breaks is listed with its count. The statement that a tie
-- "holds" in docs means 0 provider-years breaking at GBP 1,000, to the rounding of the provider forms.
--   OPERATING_SECTION / INVESTING_SECTION / FINANCING_SECTION
--       the published subtotal (SCF0180, SCF0240, SCF0315) against the sum of the published lines of that section
--   NET_CHANGE_FROM_SECTIONS
--       the published increase in cash (SCF0320) against the three published subtotals added
--   CASH_RECONCILIATION
--       closing cash (SCF0355) against opening cash (SCF0325A), the prior period adjustment (SCF0325B), the increase
--       (SCF0320) and the four other reconciling lines (SCF0345, SCF0350, SCF0115, SCF0340)
--   CLOSING_CASH_VS_BALANCE_SHEET
--       closing cash of the cash flow (SCF0355) against the balance sheet cash and cash equivalents (BAL1240)
--   NET_CHANGE_VS_BALANCE_SHEET_MOVEMENT
--       the published increase in cash (SCF0320) against the balance sheet cash movement (BAL1240, CY less PY)
--   NET_CHANGE_AND_RECONCILING_ITEMS_VS_BALANCE_SHEET_MOVEMENT
--       the increase plus the prior period adjustment and the four other reconciling lines, against the same movement
--   SOCF_OPERATING_SURPLUS_VS_SOCI
--       the operating surplus the cash flow starts from (SCF0100A) against the income statement's (SCI0140A)
--   SOCI_SURPLUS_FROM_LINES
--       the surplus for the year (SCI0240) against the 11 income-statement lines the derived cash flow uses as flows
--   DERIVED_TOTAL_VS_BALANCE_SHEET_MOVEMENT
--       the derived cash flow added over all its lines (dw.tac_cash_flow_derived) against the balance sheet cash movement

DROP TABLE IF EXISTS audit.tac_cash_flow_tie;
GO

WITH flow_line AS (
    SELECT DISTINCT m.sub_code FROM stg.tac_cash_flow_map AS m WHERE m.treatment = 'derive' AND m.basis = 'flow'
),
v AS (
    SELECT f.provider_key, f.release, f.period_column, l.sub_code, l.section, l.line_kind, l.statement, f.value,
           CASE WHEN fl.sub_code IS NOT NULL THEN 1 ELSE 0 END AS is_flow
    FROM dw.tac_fact AS f
    JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key
    LEFT JOIN flow_line AS fl ON fl.sub_code = l.sub_code
),
pv AS (
    SELECT provider_key, release,
        SUM(CASE WHEN period_column = 'CY' AND sub_code = 'SCF0180' THEN value END) AS op_sub,
        SUM(CASE WHEN period_column = 'CY' AND section = 'Operating activities' AND line_kind = 'line' THEN value END) AS op_lines,
        SUM(CASE WHEN period_column = 'CY' AND sub_code = 'SCF0240' THEN value END) AS inv_sub,
        SUM(CASE WHEN period_column = 'CY' AND section = 'Investing activities' AND line_kind = 'line' THEN value END) AS inv_lines,
        SUM(CASE WHEN period_column = 'CY' AND sub_code = 'SCF0315' THEN value END) AS fin_sub,
        SUM(CASE WHEN period_column = 'CY' AND section = 'Financing activities' AND line_kind = 'line' THEN value END) AS fin_lines,
        SUM(CASE WHEN period_column = 'CY' AND sub_code = 'SCF0320' THEN value END) AS net_change,
        SUM(CASE WHEN period_column = 'CY' AND sub_code = 'SCF0355' THEN value END) AS cf_close,
        SUM(CASE WHEN period_column = 'CY' AND sub_code = 'SCF0325A' THEN value END) AS cf_open,
        SUM(CASE WHEN period_column = 'CY' AND sub_code = 'SCF0325B' THEN value END) AS cf_prior_adj,
        SUM(CASE WHEN period_column = 'CY' AND sub_code IN ('SCF0345', 'SCF0350', 'SCF0115', 'SCF0340') THEN value END) AS cf_other_recon,
        SUM(CASE WHEN period_column = 'CY' AND sub_code = 'BAL1240' THEN value END) AS bs_cash_close,
        SUM(CASE WHEN period_column = 'PY' AND sub_code = 'BAL1240' THEN value END) AS bs_cash_open,
        SUM(CASE WHEN period_column = 'CY' AND sub_code = 'SCF0100A' THEN value END) AS cf_op_surplus,
        SUM(CASE WHEN period_column = 'CY' AND sub_code = 'SCI0140A' THEN value END) AS soci_op_surplus,
        SUM(CASE WHEN period_column = 'CY' AND sub_code = 'SCI0240' THEN value END) AS soci_surplus,
        SUM(CASE WHEN period_column = 'CY' AND is_flow = 1 THEN value END) AS soci_flow_lines
    FROM v
    GROUP BY provider_key, release
),
derived AS (
    SELECT provider_key, release, SUM(amount) AS derived_total FROM dw.tac_cash_flow_derived GROUP BY provider_key, release
),
tie AS (
    SELECT pv.release, 'OPERATING_SECTION' AS tie_code, N'Published net cash from operations against the sum of its published lines' AS description,
           pv.op_sub AS l, pv.op_lines AS r FROM pv WHERE pv.op_sub IS NOT NULL
    UNION ALL SELECT release, 'INVESTING_SECTION', N'Published net cash from investing against the sum of its published lines', inv_sub, inv_lines FROM pv WHERE inv_sub IS NOT NULL
    UNION ALL SELECT release, 'FINANCING_SECTION', N'Published net cash from financing against the sum of its published lines', fin_sub, fin_lines FROM pv WHERE fin_sub IS NOT NULL
    UNION ALL SELECT release, 'NET_CHANGE_FROM_SECTIONS', N'Published increase in cash against the three published section subtotals added', net_change, op_sub + inv_sub + fin_sub FROM pv WHERE net_change IS NOT NULL
    UNION ALL SELECT release, 'CASH_RECONCILIATION', N'Published closing cash against opening cash, the prior period adjustment, the increase and the four other reconciling lines', cf_close,
              cf_open + cf_prior_adj + net_change + cf_other_recon FROM pv WHERE cf_close IS NOT NULL
    UNION ALL SELECT release, 'CLOSING_CASH_VS_BALANCE_SHEET', N'Closing cash of the cash flow against the balance sheet cash and cash equivalents', cf_close, bs_cash_close FROM pv WHERE cf_close IS NOT NULL AND bs_cash_close IS NOT NULL
    UNION ALL SELECT release, 'NET_CHANGE_VS_BALANCE_SHEET_MOVEMENT', N'Published increase in cash against the balance sheet cash movement of the year', net_change, bs_cash_close - bs_cash_open FROM pv WHERE net_change IS NOT NULL AND bs_cash_close IS NOT NULL
    UNION ALL SELECT release, 'NET_CHANGE_AND_RECONCILING_ITEMS_VS_BALANCE_SHEET_MOVEMENT', N'Published increase in cash plus the prior period adjustment and the four other reconciling lines, against the balance sheet cash movement',
              net_change + cf_prior_adj + cf_other_recon, bs_cash_close - bs_cash_open FROM pv WHERE net_change IS NOT NULL AND bs_cash_close IS NOT NULL
    UNION ALL SELECT release, 'SOCF_OPERATING_SURPLUS_VS_SOCI', N'Operating surplus the cash flow starts from against the income statement operating surplus', cf_op_surplus, soci_op_surplus FROM pv WHERE cf_op_surplus IS NOT NULL AND soci_op_surplus IS NOT NULL
    UNION ALL SELECT release, 'SOCI_SURPLUS_FROM_LINES', N'Surplus for the year against the income statement lines the derived cash flow uses as flows', soci_surplus, soci_flow_lines FROM pv WHERE soci_surplus IS NOT NULL
    UNION ALL SELECT pv.release, 'DERIVED_TOTAL_VS_BALANCE_SHEET_MOVEMENT', N'Derived cash flow added over all its lines against the balance sheet cash movement of the year', d.derived_total, pv.bs_cash_close - pv.bs_cash_open
              FROM pv JOIN derived AS d ON d.provider_key = pv.provider_key AND d.release = pv.release WHERE pv.bs_cash_close IS NOT NULL
)
SELECT CAST(release AS varchar(7)) AS release, CAST(tie_code AS varchar(80)) AS tie_code, CAST(MAX(description) AS nvarchar(300)) AS description,
       COUNT_BIG(*) AS provider_years,
       SUM(CASE WHEN ABS(l - r) >= 1 THEN 1 ELSE 0 END) AS provider_years_breaking_1k,
       CAST(MAX(ABS(l - r)) AS decimal(19,4)) AS max_abs_difference,
       CAST(SUM(l) AS decimal(19,4)) AS left_total,
       CAST(SUM(r) AS decimal(19,4)) AS right_total
INTO audit.tac_cash_flow_tie
FROM tie
GROUP BY release, tie_code;
GO
ALTER TABLE audit.tac_cash_flow_tie ALTER COLUMN release varchar(7) NOT NULL;
GO
ALTER TABLE audit.tac_cash_flow_tie ALTER COLUMN tie_code varchar(80) NOT NULL;
GO
ALTER TABLE audit.tac_cash_flow_tie ADD CONSTRAINT pk_audit_tac_cash_flow_tie PRIMARY KEY (release, tie_code);
GO
