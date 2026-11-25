-- requires: authored.allocation_rule, dw.allocation_pool, dw.fact_allocation, audit.allocation_year_summary, synthetic.whatif_parameter
-- Independent of the model views: the rows of the base tables.
SELECT N'Allocation Rule' AS table_name, COUNT_BIG(*) AS row_count FROM authored.allocation_rule
UNION ALL SELECT N'Allocation Bridge (derived)', COUNT_BIG(*) FROM dw.fact_allocation
UNION ALL SELECT N'Allocation Coverage (derived)', COUNT_BIG(*) FROM audit.allocation_year_summary
UNION ALL SELECT N'What-if Setting (synthetic)', COUNT_BIG(*) FROM synthetic.whatif_parameter
ORDER BY table_name;
