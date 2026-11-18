-- Independent of the model: the three facts summed on their own, with no join. The outturn fact holds no row of the
-- Plan (phased) scenario (checked here); dw.fact_plan has no scenario column and the model reads it as the Plan
-- scenario only, so under the Plan (phased) scenario its measure is blank by construction (expected 1).
SELECT N'Outturn, all' AS name, CAST(SUM(amount_delta) AS decimal(38, 4)) AS value FROM dw.fact_outturn
UNION ALL
SELECT N'Plan, all', CAST(SUM(amount) AS decimal(38, 4)) FROM dw.fact_plan WHERE is_part_of_other_measure = 0
UNION ALL
SELECT N'Plan (phased), all', CAST(SUM(amount) AS decimal(38, 4)) FROM dw.fact_plan_phased WHERE is_part_of_other_measure = 0
UNION ALL
SELECT N'Outturn on scenario Plan (phased) is blank',
       CAST(CASE WHEN NOT EXISTS (SELECT 1 FROM dw.fact_outturn AS f JOIN dw.dim_scenario AS s ON s.scenario_key = f.scenario_key
                                  WHERE s.scenario_name = N'Plan (phased)') THEN 1 ELSE 0 END AS decimal(38, 4))
UNION ALL
SELECT N'Plan on scenario Plan (phased) is blank', CAST(1 AS decimal(38, 4))
UNION ALL
SELECT N'Plan (phased) rows', CAST(COUNT_BIG(*) AS decimal(38, 4)) FROM dw.fact_plan_phased
UNION ALL
SELECT N'Plan rows', CAST(COUNT_BIG(*) AS decimal(38, 4)) FROM dw.fact_plan
ORDER BY name;
