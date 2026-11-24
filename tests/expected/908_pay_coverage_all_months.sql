-- requires: audit.workforce_mapping_coverage
-- Independent of the model view: the published coverage audit of the workforce load added over every series and month, one row
-- for each figure.
WITH t AS (
    SELECT COUNT_BIG(*) AS series_months,
           SUM(paybill_total) AS paybill_published, SUM(paybill_mapped) AS paybill_mapped,
           SUM(paybill_mapped) / NULLIF(SUM(paybill_total), 0) AS paybill_coverage,
           SUM(fte_mapped) / NULLIF(SUM(fte_total), 0) AS fte_coverage
    FROM audit.workforce_mapping_coverage
)
SELECT u.item, CAST(u.value AS decimal(38, 6)) AS value
FROM t
CROSS APPLY (VALUES ('series_months', CAST(t.series_months AS decimal(38, 10))), ('paybill_published', t.paybill_published),
                    ('paybill_mapped', t.paybill_mapped), ('paybill_coverage', t.paybill_coverage), ('fte_coverage', t.fte_coverage)) AS u (item, value)
ORDER BY u.item;
