-- test: the derived cash flow adds up to the balance sheet cash movement in every provider-year to within GBP 2,000 (two columns of balance sheets that each balance to less than GBP 1,000); and the three ties that do not hold exactly are pinned: the published increase in cash against the balance sheet cash movement, the same with the reconciling lines, and closing cash against the balance sheet cash, by year, in provider-years breaking GBP 1,000
-- marker: localdata
-- requires: audit.tac_cash_flow_tie
SELECT release, tie_code, CAST(provider_years_breaking_1k AS nvarchar(20)) AS got, CAST(NULL AS nvarchar(20)) AS expected
FROM audit.tac_cash_flow_tie
WHERE tie_code = 'DERIVED_TOTAL_VS_BALANCE_SHEET_MOVEMENT' AND max_abs_difference >= 2
UNION ALL
SELECT t.release, t.tie_code, CAST(a.provider_years_breaking_1k AS nvarchar(20)), CAST(t.breaks AS nvarchar(20))
FROM (VALUES
    ('2019-20', 'NET_CHANGE_VS_BALANCE_SHEET_MOVEMENT', 15), ('2020-21', 'NET_CHANGE_VS_BALANCE_SHEET_MOVEMENT', 19),
    ('2021-22', 'NET_CHANGE_VS_BALANCE_SHEET_MOVEMENT', 12), ('2022-23', 'NET_CHANGE_VS_BALANCE_SHEET_MOVEMENT', 4),
    ('2023-24', 'NET_CHANGE_VS_BALANCE_SHEET_MOVEMENT', 8),  ('2024-25', 'NET_CHANGE_VS_BALANCE_SHEET_MOVEMENT', 14),
    ('2019-20', 'NET_CHANGE_AND_RECONCILING_ITEMS_VS_BALANCE_SHEET_MOVEMENT', 5), ('2020-21', 'NET_CHANGE_AND_RECONCILING_ITEMS_VS_BALANCE_SHEET_MOVEMENT', 6),
    ('2021-22', 'NET_CHANGE_AND_RECONCILING_ITEMS_VS_BALANCE_SHEET_MOVEMENT', 4), ('2022-23', 'NET_CHANGE_AND_RECONCILING_ITEMS_VS_BALANCE_SHEET_MOVEMENT', 2),
    ('2023-24', 'NET_CHANGE_AND_RECONCILING_ITEMS_VS_BALANCE_SHEET_MOVEMENT', 4), ('2024-25', 'NET_CHANGE_AND_RECONCILING_ITEMS_VS_BALANCE_SHEET_MOVEMENT', 2),
    ('2019-20', 'CLOSING_CASH_VS_BALANCE_SHEET', 4), ('2020-21', 'CLOSING_CASH_VS_BALANCE_SHEET', 2),
    ('2021-22', 'CLOSING_CASH_VS_BALANCE_SHEET', 2), ('2022-23', 'CLOSING_CASH_VS_BALANCE_SHEET', 1),
    ('2023-24', 'CLOSING_CASH_VS_BALANCE_SHEET', 2), ('2024-25', 'CLOSING_CASH_VS_BALANCE_SHEET', 1)
) AS t(release, tie_code, breaks)
LEFT JOIN audit.tac_cash_flow_tie AS a ON a.release = t.release AND a.tie_code = t.tie_code
WHERE a.provider_years_breaking_1k IS NULL OR a.provider_years_breaking_1k <> t.breaks;
