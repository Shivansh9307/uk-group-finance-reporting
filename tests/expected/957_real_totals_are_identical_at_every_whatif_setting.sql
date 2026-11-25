-- requires: dw.fact_outturn, dw.fact_plan, dw.fact_allocation, synthetic.whatif_parameter
-- Independent of the model views and of the what-if table's values: the total of the real outturn deltas, of the plan rows, of the
-- allocated amounts and of the annualised paybill, repeated on every setting row (the settings give only the labels).
WITH t AS (
    SELECT (SELECT CAST(SUM(amount_delta) AS decimal(38, 4)) FROM dw.fact_outturn) AS outturn,
           (SELECT COUNT_BIG(*) FROM dw.fact_plan) AS plan_rows,
           (SELECT CAST(SUM(allocated_amount) AS decimal(38, 4)) FROM dw.fact_allocation) AS allocated,
           (SELECT CAST(SUM(paybill_annualised) AS decimal(38, 4)) FROM dw.fact_allocation) AS paybill
),
s AS (
    SELECT CAST(0 AS varchar(2)) + ' none selected' AS setting
    UNION ALL
    SELECT CAST(w.setting_key AS varchar(10)) + ' ' + w.setting_name FROM synthetic.whatif_parameter AS w
)
SELECT s.setting, t.outturn, t.plan_rows, t.allocated, t.paybill
FROM s CROSS JOIN t
ORDER BY s.setting;
