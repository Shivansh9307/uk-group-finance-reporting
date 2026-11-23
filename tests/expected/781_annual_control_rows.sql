-- requires: audit.bud_vs_inyear_del
-- Independent of the model: audit.bud_vs_inyear_del as the build wrote it.
SELECT financial_year, vintage, level, inyear_release, CAST(inyear_amount AS decimal(38, 4)) AS inyear_amount,
       CAST(bud_amount AS decimal(38, 4)) AS annual_amount, CAST(gap AS decimal(38, 4)) AS gap,
       CAST(gap_share_of_bud * 1000000 AS decimal(38, 4)) AS gap_share_ppm, status
FROM audit.bud_vs_inyear_del
ORDER BY financial_year, vintage, level, inyear_release;
