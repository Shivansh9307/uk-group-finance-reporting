-- test: for each department series, published name and month no more than one authored map row applies
-- marker: localdata
-- requires: stg.workforce_org_map, stg.workforce_row
SELECT TOP (20) r.dept, r.name_key, r.period_start, COUNT(DISTINCT m.map_id) AS map_rows
FROM stg.workforce_row AS r
JOIN stg.workforce_org_map AS m
  ON m.dept = r.dept AND m.name_key = r.name_key
 AND (m.valid_from IS NULL OR m.valid_from <= r.period_start)
 AND (m.valid_to IS NULL OR m.valid_to >= r.period_start)
WHERE r.is_primary = 1
GROUP BY r.dept, r.name_key, r.period_start
HAVING COUNT(DISTINCT m.map_id) > 1;
