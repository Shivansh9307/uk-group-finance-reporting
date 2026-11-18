-- test: the phased plan and the phasing profile are flagged derived, labelled DERIVED, and nothing outside this feature reads or points at the phased plan (the row counts and sums of the real facts are pinned in evidence/expected/real_fact_totals.csv and checked by pipeline/tests/test_real_totals.py)
SELECT 'derived row not flagged' AS problem, 'dw.plan_phasing_profile' AS detail, CAST(NULL AS nvarchar(100)) AS got, CAST(NULL AS nvarchar(100)) AS expected
FROM dw.plan_phasing_profile WHERE is_derived <> 1 GROUP BY is_derived
UNION ALL
SELECT 'derived row not flagged', 'dw.fact_plan_phased', NULL, NULL FROM dw.fact_plan_phased WHERE is_derived <> 1 GROUP BY is_derived
UNION ALL
SELECT 'table description does not say DERIVED', t.name, NULL, NULL
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE s.name = 'dw' AND t.name IN ('plan_phasing_profile', 'fact_plan_phased')
  AND NOT EXISTS (SELECT 1 FROM sys.extended_properties AS p
                  WHERE p.class = 1 AND p.major_id = t.object_id AND p.minor_id = 0 AND p.name = N'MS_Description'
                    AND CAST(p.value AS nvarchar(max)) LIKE N'DERIVED%')
UNION ALL
SELECT 'a view or procedure reads the phased plan', OBJECT_SCHEMA_NAME(d.referencing_id) + '.' + OBJECT_NAME(d.referencing_id), NULL, NULL
FROM sys.sql_expression_dependencies AS d
WHERE d.referenced_id = OBJECT_ID('dw.fact_plan_phased')
UNION ALL
SELECT 'a foreign key points at the phased plan', OBJECT_NAME(fk.parent_object_id), NULL, NULL
FROM sys.foreign_keys AS fk WHERE fk.referenced_object_id = OBJECT_ID('dw.fact_plan_phased')
UNION ALL
SELECT 'phased scenario is not marked derived in dim_scenario', scenario_name, NULL, NULL
FROM dw.dim_scenario WHERE scenario_name = N'Plan (phased)' AND is_derived <> 1
UNION ALL
SELECT 'a phased row uses the outturn scenario', 'dw.fact_plan_phased', NULL, NULL
FROM dw.fact_plan_phased AS x JOIN dw.dim_scenario AS s ON s.scenario_key = x.scenario_key
WHERE s.scenario_name = N'Outturn' GROUP BY s.scenario_name;
