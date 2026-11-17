-- test: PSS against BUD passes its tolerance for resource DEL excluding depreciation in every year; the only failures are capital DEL in 2023-24 and 2024-25; PSS totals tie to the PSS rows
-- marker: localdata
-- requires: audit.pss_vs_outturn, stg.pss_outturn
SELECT N'BUD resource DEL excl depreciation control row not pass' AS problem, CONCAT(financial_year, N' ', status) AS detail
FROM audit.pss_vs_outturn
WHERE comparison = 'BUD' AND level = 'TOTAL EXCL SCOTLAND' AND measure = 'RDEL_EX_DEPN' AND status <> 'pass'
UNION ALL
SELECT N'unexpected failure (known: BUD capital DEL, 2023-24 and 2024-25, about -0.4%)', CONCAT(financial_year, N' ', measure)
FROM audit.pss_vs_outturn
WHERE status = 'fail' AND NOT (comparison = 'BUD' AND measure = 'CDEL' AND level = 'TOTAL EXCL SCOTLAND'
                                AND financial_year IN ('2023-24', '2024-25'))
UNION ALL
SELECT N'known capital DEL failures changed', CAST(COUNT(*) AS nvarchar(200))
FROM audit.pss_vs_outturn WHERE status = 'fail' HAVING COUNT(*) <> 2
UNION ALL
SELECT N'comparison years are not 4 BUD and 5 in-year', CONCAT(comparison, N' ', CAST(COUNT(DISTINCT financial_year) AS nvarchar(5)))
FROM audit.pss_vs_outturn GROUP BY comparison
HAVING (comparison = 'BUD' AND COUNT(DISTINCT financial_year) <> 4)
    OR (comparison = 'IN-YEAR' AND COUNT(DISTINCT financial_year) <> 5)
UNION ALL
SELECT N'PSS total differs from the PSS rows', CONCAT(a.financial_year, N' ', a.measure)
FROM audit.pss_vs_outturn AS a
JOIN (SELECT financial_year,
             CASE WHEN basis_rdel_excl_depreciation = 1 THEN 'RDEL_EX_DEPN' ELSE 'CDEL' END AS measure,
             SUM(amount) AS amount
      FROM stg.pss_outturn
      WHERE basis_rdel_excl_depreciation = 1 OR (control_budget_code = 'DEL' AND economic_budget_code = 'CAPITAL')
      GROUP BY financial_year, CASE WHEN basis_rdel_excl_depreciation = 1 THEN 'RDEL_EX_DEPN' ELSE 'CDEL' END) AS p
  ON p.financial_year = a.financial_year AND p.measure = a.measure
WHERE a.level = 'TOTAL' AND a.pss_amount <> p.amount
UNION ALL
SELECT N'BUD total differs from the fact table', CONCAT(a.financial_year, N' ', a.measure)
FROM audit.pss_vs_outturn AS a
JOIN (SELECT f.financial_year,
             CASE WHEN f.basis_rdel_excl_depreciation = 1 THEN 'RDEL_EX_DEPN' ELSE 'CDEL' END AS measure,
             SUM(f.amount) AS amount
      FROM dw.fact_outturn_annual AS f
      WHERE (f.basis_rdel_excl_depreciation = 1 OR (f.control_budget_code = 'DEL' AND f.economic_budget_code = 'CAPITAL'))
        AND f.vintage = (SELECT MAX(vintage) FROM raw.oscar_bud_file WHERE financial_year = f.financial_year AND file_kind = 'data')
      GROUP BY f.financial_year, CASE WHEN f.basis_rdel_excl_depreciation = 1 THEN 'RDEL_EX_DEPN' ELSE 'CDEL' END) AS b
  ON b.financial_year = a.financial_year AND b.measure = a.measure
WHERE a.comparison = 'BUD' AND a.level = 'TOTAL' AND a.oscar_amount <> b.amount
UNION ALL
SELECT N'a group row is not matched to an OSCAR group', CONCAT(comparison, N' ', financial_year, N' ', measure)
FROM audit.pss_vs_outturn WHERE level = 'SR GROUP' AND sr_group_name = N'UNMATCHED' AND pss_amount <> 0;
