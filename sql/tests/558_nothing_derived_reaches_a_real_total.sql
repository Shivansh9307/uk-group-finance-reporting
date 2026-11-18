-- test: the real facts are what they were before the phasing files existed (row counts and sums recorded from a build of main before these files, per build scope); the phased plan and the profile are flagged derived, labelled DERIVED, and nothing outside this feature reads the phased plan
WITH scope AS (
    SELECT CAST(value AS varchar(20)) AS scope FROM sys.extended_properties WHERE class = 0 AND name = N'ukfr_build_scope'
), facts AS (
    SELECT 'dw.fact_outturn' AS fact, COUNT_BIG(*) AS n, SUM(amount_delta) AS total FROM dw.fact_outturn
    UNION ALL
    SELECT 'dw.fact_plan', COUNT_BIG(*), SUM(amount) FROM dw.fact_plan
), expected AS (
    SELECT 'dw.fact_outturn' AS fact, CAST(658554 AS bigint) AS n, CAST(9098653566.4360 AS decimal(28, 4)) AS total, 'committed' AS scope
    UNION ALL SELECT 'dw.fact_outturn', 658554, 9098653566.4360, 'full'
    UNION ALL SELECT 'dw.fact_plan', 749, 7785863653.0000, 'committed'
    UNION ALL SELECT 'dw.fact_plan', 5372, 21532485408.0000, 'full'
)
SELECT 'real fact changed' AS problem, r.fact AS detail, CONCAT(r.n, ' rows, ', r.total) AS got, CONCAT(e.n, ' rows, ', e.total) AS expected
FROM facts AS r
JOIN scope AS s ON 1 = 1
JOIN expected AS e ON e.fact = r.fact AND e.scope = s.scope
WHERE r.n <> e.n OR r.total <> e.total
UNION ALL
SELECT 'derived row not flagged', 'dw.plan_phasing_profile', NULL, NULL FROM dw.plan_phasing_profile WHERE is_derived <> 1 GROUP BY is_derived
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
