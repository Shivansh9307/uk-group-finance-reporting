-- test: the organisation, department, segment, account and control budget dimensions each have exactly one Unknown member with key -1
SELECT t.dimension, t.members_with_minus_one
FROM (
    SELECT 'dim_organisation' AS dimension, (SELECT COUNT(*) FROM dw.dim_organisation WHERE organisation_key = -1) AS members_with_minus_one
    UNION ALL SELECT 'dim_department', (SELECT COUNT(*) FROM dw.dim_department WHERE department_key = -1)
    UNION ALL SELECT 'dim_segment', (SELECT COUNT(*) FROM dw.dim_segment WHERE segment_key = -1 AND segment_name = N'Unknown')
    UNION ALL SELECT 'dim_account', (SELECT COUNT(*) FROM dw.dim_account WHERE account_key = -1 AND economic_category_name = N'Unknown')
    UNION ALL SELECT 'dim_control_budget', (SELECT COUNT(*) FROM dw.dim_control_budget WHERE control_budget_key = -1 AND control_budget_detail = N'Unknown')
) AS t
WHERE t.members_with_minus_one <> 1;
