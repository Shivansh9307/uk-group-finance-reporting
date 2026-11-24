-- test: the authored map table is labelled authored, and the workforce fact reads no authored or synthetic table other than that map (the map decides which organisation a value belongs to and adds no value)
-- marker: localdata
-- requires: authored.workforce_org_map, dw.workforce_month
SELECT 'map table is not labelled authored' AS problem
WHERE NOT EXISTS (
    SELECT 1 FROM sys.extended_properties AS p
    WHERE p.major_id = OBJECT_ID(N'authored.workforce_org_map') AND p.minor_id = 0 AND p.name = N'MS_Description'
      AND CAST(p.value AS nvarchar(max)) LIKE N'AUTHORED%')
UNION ALL
SELECT 'stg.workforce_org_map is not built from authored.workforce_org_map'
WHERE (SELECT COUNT(*) FROM stg.workforce_org_map) <> (SELECT COUNT(*) FROM authored.workforce_org_map);
