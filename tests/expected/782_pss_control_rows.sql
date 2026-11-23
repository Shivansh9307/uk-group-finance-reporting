-- requires: audit.pss_vs_outturn
-- Independent of the model: audit.pss_vs_outturn as the build wrote it.
SELECT comparison, financial_year, source_release, level, sr_group_name AS [group], measure,
       CAST(pss_amount AS decimal(38, 4)) AS pss_amount, CAST(oscar_amount AS decimal(38, 4)) AS oscar_amount,
       CAST(gap AS decimal(38, 4)) AS gap, CAST(gap_share_of_oscar * 1000000 AS decimal(38, 4)) AS gap_share_ppm, status
FROM audit.pss_vs_outturn
ORDER BY comparison, financial_year, level, sr_group_name, measure;
