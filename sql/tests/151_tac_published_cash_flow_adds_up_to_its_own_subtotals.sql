-- test: in every provider-year the published cash flow adds up to itself, to the rounding of the provider forms (less than GBP 1,000): each section subtotal equals the sum of its published lines, the increase in cash equals the three subtotals, closing cash equals opening cash plus the adjustments, the increase and the reconciling lines, the operating surplus the cash flow starts from equals the income statement's, and the income-statement surplus equals the lines the derived cash flow uses
-- marker: localdata
-- requires: audit.tac_cash_flow_tie
SELECT release, tie_code, provider_years_breaking_1k, max_abs_difference
FROM audit.tac_cash_flow_tie
WHERE tie_code IN ('OPERATING_SECTION', 'INVESTING_SECTION', 'FINANCING_SECTION', 'NET_CHANGE_FROM_SECTIONS',
                   'CASH_RECONCILIATION', 'SOCF_OPERATING_SURPLUS_VS_SOCI', 'SOCI_SURPLUS_FROM_LINES')
  AND (provider_years_breaking_1k <> 0 OR max_abs_difference >= 1)
UNION ALL
-- every tie has a row in every year, and the provider-years compared are the providers with statements
SELECT y.release, t.tie_code, NULL, NULL
FROM (SELECT DISTINCT release FROM dw.tac_fact) AS y
CROSS JOIN (VALUES ('OPERATING_SECTION'), ('INVESTING_SECTION'), ('FINANCING_SECTION'), ('NET_CHANGE_FROM_SECTIONS'),
                   ('CASH_RECONCILIATION'), ('CLOSING_CASH_VS_BALANCE_SHEET'), ('NET_CHANGE_VS_BALANCE_SHEET_MOVEMENT'),
                   ('NET_CHANGE_AND_RECONCILING_ITEMS_VS_BALANCE_SHEET_MOVEMENT'), ('SOCF_OPERATING_SURPLUS_VS_SOCI'),
                   ('SOCI_SURPLUS_FROM_LINES'), ('DERIVED_TOTAL_VS_BALANCE_SHEET_MOVEMENT')) AS t(tie_code)
WHERE NOT EXISTS (SELECT 1 FROM audit.tac_cash_flow_tie AS a WHERE a.release = y.release AND a.tie_code = t.tie_code
                  AND a.provider_years = (SELECT COUNT(*) FROM dw.tac_provider_year AS p WHERE p.release = y.release AND p.has_statement_data = 1));
