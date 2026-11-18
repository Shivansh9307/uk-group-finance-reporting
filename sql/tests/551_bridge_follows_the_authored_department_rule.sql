-- test: the bridge group of a pair is what authored/department_sr_group.csv says for the current department number (or the organisation exception), every current row of the file is used, and CLG Communities and CLG Local Government are split by organisation
WITH expected AS (
    SELECT b.organisation_key, b.sub_segment_code, b.bridge_rule, b.department_number, o.durable_key, b.sr_group_key,
           COALESCE((SELECT TOP 1 g.sr_group_key FROM authored.department_sr_group AS r JOIN dw.dim_sr_group AS g ON g.sr_group_code = r.sr_group_code
                     WHERE r.department_number = b.department_number AND r.basis = 'current' AND r.durable_key = o.durable_key),
                    (SELECT TOP 1 g.sr_group_key FROM authored.department_sr_group AS r JOIN dw.dim_sr_group AS g ON g.sr_group_code = r.sr_group_code
                     WHERE r.department_number = b.department_number AND r.basis = 'current' AND r.durable_key = ''),
                    (SELECT sr_group_key FROM dw.dim_sr_group WHERE sr_group_code = 'OUTTURN_ONLY_UNALLOC')) AS want
    FROM dw.outturn_sr_group_bridge AS b
    JOIN dw.dim_organisation AS o ON o.organisation_key = b.organisation_key
)
SELECT 'bridge group differs from the authored rule' AS problem, CAST(organisation_key AS nvarchar(20)) AS detail, sub_segment_code AS detail2
FROM expected WHERE sr_group_key <> want
UNION ALL
SELECT 'current row of the file never used', r.department_number, r.durable_key
FROM authored.department_sr_group AS r
WHERE r.basis = 'current'
  AND NOT EXISTS (SELECT 1 FROM dw.outturn_sr_group_bridge AS b JOIN dw.dim_organisation AS o ON o.organisation_key = b.organisation_key
                  WHERE b.department_number = r.department_number AND (r.durable_key = '' OR o.durable_key = r.durable_key))
UNION ALL
SELECT 'department 085 organisations are not split into two groups', CAST(COUNT(DISTINCT sr_group_key) AS nvarchar(20)), NULL
FROM dw.outturn_sr_group_bridge WHERE department_number = '085'
HAVING COUNT(DISTINCT sr_group_key) <> 2
UNION ALL
SELECT 'an exception pair is not in the exception organisation', CAST(organisation_key AS nvarchar(20)), sub_segment_code
FROM dw.outturn_sr_group_bridge AS b
WHERE bridge_rule = 'organisation exception' AND durable_key NOT IN
      (SELECT durable_key FROM authored.department_sr_group WHERE durable_key <> '' AND basis = 'current')
UNION ALL
SELECT 'Unallocated department member not bridged to the outturn-only member', CAST(b.organisation_key AS nvarchar(20)), b.sub_segment_code
FROM dw.outturn_sr_group_bridge AS b
JOIN dw.dim_department AS d ON d.department_key = b.current_department_key
JOIN dw.dim_sr_group AS g ON g.sr_group_key = b.sr_group_key
WHERE d.member_type = 'Unallocated' AND (b.bridge_rule <> 'unallocated member' OR g.sr_group_code <> 'OUTTURN_ONLY_UNALLOC')
UNION ALL
SELECT 'pair bridged as unallocated whose department is not an Unallocated member', CAST(b.organisation_key AS nvarchar(20)), b.sub_segment_code
FROM dw.outturn_sr_group_bridge AS b
JOIN dw.dim_department AS d ON d.department_key = b.current_department_key
WHERE b.bridge_rule = 'unallocated member' AND d.member_type <> 'Unallocated'
UNION ALL
SELECT 'bridge group is a pre-2023 combined, plan-only or non-department member', CAST(b.organisation_key AS nvarchar(20)), b.sub_segment_code
FROM dw.outturn_sr_group_bridge AS b
JOIN dw.dim_sr_group AS g ON g.sr_group_key = b.sr_group_key
WHERE g.member_type IN ('combined_pre_2023', 'plan_only', 'non_department');
