-- Independent of the model: the rows and paybill of the published coverage audit of the workforce load, which no department
-- filter reaches.
SELECT COUNT_BIG(*) AS coverage_rows,
       CAST(SUM(paybill_total) AS decimal(38, 4)) AS paybill_published,
       CAST(SUM(paybill_mapped) AS decimal(38, 4)) AS paybill_mapped
FROM audit.workforce_mapping_coverage;
