-- test: the organisations on which the bridge and the newest annual release (BUD) disagree about the Spending Review group are exactly the 31 (organisation, bridge group) pairs listed here and read in docs/data-dictionary/plan-phasing.md; every other organisation present in both agrees; only BIS084 (the BEIS core department, whose lines the current structure splits between four groups) has more than one row
-- marker: localdata
-- requires: audit.sr_group_bridge_vs_bud
WITH expected (organisation_code, bridge_group_code, bud_group_code) AS (
    SELECT * FROM (VALUES
        ('ACA084', 'SR_013', 'SR_084'), ('ARA035', 'NONDEPT_UNALLOC', 'SR_SIB'), ('BBB084', 'SR_013', 'SR_084'),
        ('BIS084', 'NONDEPT_UNALLOC', 'SR_084'), ('BIS084', 'SR_013', 'SR_084'), ('BIS084', 'SR_022', 'SR_084'),
        ('BIS084', 'SR_066', 'SR_084'), ('BPA084', 'SR_013', 'SR_084'), ('CCC084', 'SR_066', 'SR_084'),
        ('CIS084', 'SR_013', 'SR_084'), ('CNC084', 'SR_066', 'SR_084'), ('COL084', 'SR_066', 'SR_084'),
        ('CSE084', 'SR_013', 'SR_084'), ('EHL084', 'SR_066', 'SR_084'), ('ELC011', 'NONDEPT_UNALLOC', 'SR_SIB'),
        ('ESC084', 'SR_066', 'SR_084'), ('FFL084', 'SR_013', 'SR_084'), ('FRC084', 'SR_013', 'SR_084'),
        ('ICO048', 'SR_084', 'SR_048'), ('LCC084', 'SR_066', 'SR_084'), ('MEI084', 'SR_013', 'SR_084'),
        ('NDA084', 'SR_066', 'SR_084'), ('NPI084', 'SR_013', 'SR_084'), ('OFC048', 'SR_084', 'SR_048'),
        ('OGA084', 'SR_066', 'SR_084'), ('PSH084', 'NONDEPT_UNALLOC', 'SR_084'), ('SAL084', 'SR_066', 'SR_084'),
        ('SCG084', 'SR_066', 'SR_084'), ('STS084', 'NONDEPT_UNALLOC', 'SR_084'), ('UKA084', 'SR_066', 'SR_084'),
        ('UKG084', 'SR_066', 'SR_084')) AS v (organisation_code, bridge_group_code, bud_group_code)
)
SELECT 'disagreement that is not listed' AS problem, a.organisation_code AS detail, a.bridge_group_code AS detail2, a.bud_group_code AS detail3
FROM audit.sr_group_bridge_vs_bud AS a
WHERE a.status = 'differ'
  AND NOT EXISTS (SELECT 1 FROM expected AS e WHERE e.organisation_code = a.organisation_code
                  AND e.bridge_group_code = a.bridge_group_code AND e.bud_group_code = a.bud_group_code)
UNION ALL
SELECT 'listed disagreement has gone', e.organisation_code, e.bridge_group_code, e.bud_group_code
FROM expected AS e
WHERE NOT EXISTS (SELECT 1 FROM audit.sr_group_bridge_vs_bud AS a WHERE a.status = 'differ' AND a.organisation_code = e.organisation_code
                  AND a.bridge_group_code = e.bridge_group_code AND a.bud_group_code = e.bud_group_code)
UNION ALL
SELECT 'status counts changed', status, CAST(COUNT(*) AS varchar(20)), NULL
FROM audit.sr_group_bridge_vs_bud
GROUP BY status
HAVING (status = 'agree' AND COUNT(*) <> 256)
    OR (status = 'differ' AND COUNT(*) <> 31)
    OR (status = 'not_in_bud' AND COUNT(*) <> 16)
    OR (status = 'not_in_outturn' AND COUNT(*) <> 24)
    OR status NOT IN ('agree', 'differ', 'not_in_bud', 'not_in_outturn')
UNION ALL
SELECT 'organisation in both with more than one row', organisation_code, CAST(COUNT(*) AS varchar(20)), NULL
FROM audit.sr_group_bridge_vs_bud WHERE status IN ('agree', 'differ') AND organisation_code <> 'BIS084'
GROUP BY organisation_code HAVING COUNT(*) > 1;
