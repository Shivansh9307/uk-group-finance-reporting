-- test: dw.fact_outturn_annual has one row per grain, the control budget follows the detail, and the flags follow their rules
-- marker: localdata
-- requires: dw.fact_outturn_annual, stg.bud_sr_group_by_organisation
SELECT N'duplicate grain' AS problem, CONCAT(vintage, N' ', financial_year, N' ', organisation_code) AS detail
FROM dw.fact_outturn_annual
GROUP BY vintage, financial_year, organisation_code, economic_category_code, control_budget_detail_code,
         economic_budget_code, economic_ringfence_code, type_code
HAVING COUNT(*) > 1
UNION ALL
SELECT N'control budget detail has more than one control budget', control_budget_detail_code
FROM dw.fact_outturn_annual GROUP BY control_budget_detail_code HAVING COUNT(DISTINCT control_budget_code) > 1
UNION ALL
SELECT N'unexpected control budget', control_budget_code
FROM dw.fact_outturn_annual WHERE control_budget_code NOT IN (N'DEL', N'AME', N'NON-BUDGET') GROUP BY control_budget_code
UNION ALL
SELECT N'basis flag breaks its rule',
       CONCAT(vintage, N' ', organisation_code, N' ', economic_budget_code, N' ', economic_ringfence_code)
FROM dw.fact_outturn_annual
WHERE basis_rdel_excl_depreciation <> CASE WHEN control_budget_code = N'DEL' AND economic_budget_code = N'RESOURCE'
                                              AND economic_ringfence_code <> N'RINGFENCED' THEN 1 ELSE 0 END
UNION ALL
SELECT N'Scotland flag outside the Scottish Government group', CONCAT(f.vintage, N' ', f.organisation_code)
FROM dw.fact_outturn_annual AS f
JOIN stg.bud_sr_group_by_organisation AS m
  ON m.vintage = f.vintage AND m.financial_year = f.financial_year AND m.organisation_code = f.organisation_code
WHERE f.is_dept_group_scotland <> CASE WHEN m.department_group_code = N'SCT075.GROUP' THEN 1 ELSE 0 END
UNION ALL
SELECT N'no Scotland rows in a workbook', CONCAT(vintage, N' ', financial_year)
FROM dw.fact_outturn_annual GROUP BY vintage, financial_year HAVING SUM(CAST(is_dept_group_scotland AS int)) = 0
UNION ALL
SELECT N'latest vintage flag wrong', vintage
FROM dw.fact_outturn_annual
GROUP BY vintage
HAVING MAX(CAST(is_latest_vintage AS int)) <> MIN(CAST(is_latest_vintage AS int))
    OR MAX(CAST(is_latest_vintage AS int)) <> CASE WHEN vintage = (SELECT MAX(vintage) FROM dw.fact_outturn_annual) THEN 1 ELSE 0 END;
