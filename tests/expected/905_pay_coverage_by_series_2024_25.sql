-- requires: audit.workforce_mapping_coverage
-- Independent of the model view: the published coverage table of the workforce load, by department series, for the months of
-- 2024-25 (April 2024 to March 2025). The series names are written out here, not read from the view.
SELECT CASE c.dept WHEN 'beis' THEN N'BEIS' WHEN 'cma' THEN N'CMA' WHEN 'dbt' THEN N'DBT' WHEN 'dcms' THEN N'DCMS'
                   WHEN 'defra' THEN N'Defra' WHEN 'desnz' THEN N'DESNZ' WHEN 'dfe' THEN N'DfE' WHEN 'dft' THEN N'DfT'
                   WHEN 'dhsc' THEN N'DHSC' WHEN 'dsit' THEN N'DSIT' WHEN 'dwp' THEN N'DWP' WHEN 'fcdo' THEN N'FCDO'
                   WHEN 'fsa' THEN N'FSA' WHEN 'hmlr' THEN N'HM Land Registry (own collection)' WHEN 'hmrc' THEN N'HMRC'
                   WHEN 'hmt' THEN N'HM Treasury' WHEN 'mhclg' THEN N'MHCLG' WHEN 'mod' THEN N'MOD'
                   WHEN 'nca' THEN N'NCA' WHEN 'ukef' THEN N'UK Export Finance' ELSE c.dept END AS series,
       COUNT_BIG(*) AS months,
       CAST(SUM(c.paybill_total) AS decimal(38, 4)) AS paybill_published,
       CAST(SUM(c.paybill_mapped) AS decimal(38, 4)) AS paybill_mapped,
       CAST(SUM(c.paybill_mapped) / NULLIF(SUM(c.paybill_total), 0) AS decimal(38, 6)) AS paybill_coverage,
       CAST(SUM(c.fte_mapped) / NULLIF(SUM(c.fte_total), 0) AS decimal(38, 6)) AS fte_coverage
FROM audit.workforce_mapping_coverage AS c
WHERE c.report_month >= '2024-04' AND c.report_month <= '2025-03'
GROUP BY c.dept
ORDER BY series;
