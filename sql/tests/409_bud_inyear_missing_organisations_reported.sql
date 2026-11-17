-- test: the six in-year organisation codes missing from the BUD are reported with their in-year amounts, and kept in stg.inyear_snapshot
-- marker: localdata
-- requires: audit.bud_inyear_org_match, stg.inyear_snapshot
SELECT N'in-year only codes are not the expected six' AS problem,
       ISNULL(STRING_AGG(organisation_code, N' ') WITHIN GROUP (ORDER BY organisation_code), N'') AS detail
FROM audit.bud_inyear_org_match WHERE status = 'in-year only'
HAVING ISNULL(STRING_AGG(organisation_code, N' ') WITHIN GROUP (ORDER BY organisation_code), N'')
       <> N'BSR085 GBE066 IFR048 LBC066 LCF048 LIL003'
UNION ALL
SELECT N'reported code with no in-year rows or a different total than the staging table', m.organisation_code
FROM audit.bud_inyear_org_match AS m
WHERE m.status = 'in-year only'
  AND (m.inyear_rows = 0
       OR m.inyear_rows <> (SELECT COUNT(*) FROM stg.inyear_snapshot AS s
                            WHERE s.organisation_code = m.organisation_code AND s.release = m.inyear_release)
       OR m.inyear_amount <> (SELECT SUM(s.amount) FROM stg.inyear_snapshot AS s
                              WHERE s.organisation_code = m.organisation_code AND s.release = m.inyear_release))
UNION ALL
SELECT N'in-year organisation missing from the match table', s.organisation_code
FROM (SELECT DISTINCT organisation_code FROM stg.inyear_snapshot
      WHERE release = (SELECT TOP (1) release FROM stg.release ORDER BY release_seq DESC)) AS s
WHERE NOT EXISTS (SELECT 1 FROM audit.bud_inyear_org_match AS m WHERE m.organisation_code = s.organisation_code AND m.in_inyear = 1);
