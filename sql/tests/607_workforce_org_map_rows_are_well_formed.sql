-- test: every authored workforce map row has a known department series, a decision of map or exclude, a durable key that exists in dw.dim_organisation (map) or a reason (exclude), a basis from the list, and valid months
-- marker: localdata
-- requires: stg.workforce_org_map, raw.workforce_file
SELECT TOP (20) m.map_id, m.dept, m.organisation_name, m.decision, m.durable_key, m.basis
FROM stg.workforce_org_map AS m
WHERE m.dept NOT IN (SELECT dept FROM raw.workforce_file)
   OR m.decision NOT IN ('map', 'exclude')
   OR m.name_key = ''
   OR (m.decision = 'map' AND (m.durable_key IS NULL OR m.basis IS NULL
                               OR m.basis NOT IN ('name', 'name_variant', 'agency_into_parent', 'part_of')
                               OR NOT EXISTS (SELECT 1 FROM dw.dim_organisation AS o WHERE o.durable_key = m.durable_key)))
   OR (m.decision = 'exclude' AND (m.durable_key IS NOT NULL OR m.basis IS NOT NULL OR LEN(m.reason) < 10))
   OR (m.valid_from IS NULL AND EXISTS (SELECT 1 FROM authored.workforce_org_map AS a
                                        WHERE a._load_order = m.map_id AND LTRIM(RTRIM(a.valid_from)) <> ''))
   OR (m.valid_to IS NULL AND EXISTS (SELECT 1 FROM authored.workforce_org_map AS a
                                      WHERE a._load_order = m.map_id AND LTRIM(RTRIM(a.valid_to)) <> ''))
   OR (m.valid_from IS NOT NULL AND m.valid_to IS NOT NULL AND m.valid_from > m.valid_to);
