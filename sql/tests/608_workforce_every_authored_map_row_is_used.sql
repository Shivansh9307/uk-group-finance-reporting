-- test: every row of authored.workforce_org_map decides at least one published row (no dead map rows)
-- marker: localdata
-- requires: stg.workforce_org_map, stg.workforce_row_class
SELECT TOP (20) m.map_id, m.dept, m.organisation_name, m.decision, m.durable_key
FROM stg.workforce_org_map AS m
WHERE NOT EXISTS (SELECT 1 FROM stg.workforce_row_class AS c WHERE c.map_id = m.map_id);
