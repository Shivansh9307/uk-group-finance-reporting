-- requires: audit.plan_variance_reconciliation
-- Independent of the model: audit.plan_variance_reconciliation as the build wrote it.
SELECT financial_year, sr_group_name AS [group], measure,
       CAST(plan_amount AS decimal(38, 4)) AS plan_amount, CAST(outturn AS decimal(38, 4)) AS outturn,
       CAST(variance AS decimal(38, 4)) AS variance, CAST(variance_share * 1000000 AS decimal(38, 4)) AS variance_share_ppm,
       reference_source, CAST(gap_first_look AS decimal(38, 4)) AS gap_first_look,
       CAST(gap_on_reference AS decimal(38, 4)) AS gap_on_reference, CAST(residual AS decimal(38, 4)) AS residual,
       verdict_class, verdict
FROM audit.plan_variance_reconciliation
ORDER BY financial_year, sr_group_name, measure;
