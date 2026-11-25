-- requires: synthetic.whatif_parameter, dw.fact_allocation
-- Independent of the model views: the five settings of the synthetic table applied to the 2025-26 allocated amount and annualised paybill
-- of the allocation fact. The row "0 none selected" is the default setting (the one with is_default = 1).
WITH t AS (
    SELECT CAST(SUM(allocated_amount) AS decimal(38, 10)) AS allocated, CAST(SUM(paybill_annualised) AS decimal(38, 10)) AS paybill
    FROM dw.fact_allocation WHERE financial_year = '2025-26'
),
s AS (
    SELECT CAST(0 AS varchar(2)) + ' none selected' AS setting, w.pay_award_pct, w.headcount_change_pct
    FROM synthetic.whatif_parameter AS w WHERE w.is_default = 1
    UNION ALL
    SELECT CAST(w.setting_key AS varchar(10)) + ' ' + w.setting_name, w.pay_award_pct, w.headcount_change_pct
    FROM synthetic.whatif_parameter AS w
)
SELECT s.setting,
       CAST(s.pay_award_pct / 100 AS decimal(38, 10)) AS pay_award,
       CAST(s.headcount_change_pct / 100 AS decimal(38, 10)) AS headcount_change,
       CAST(t.allocated * (1 + s.pay_award_pct / 100) AS decimal(38, 10)) AS allocated_whatif,
       CAST(t.allocated * (s.pay_award_pct / 100) AS decimal(38, 10)) AS allocated_effect,
       CAST(t.paybill * (1 + s.headcount_change_pct / 100) * (1 + s.pay_award_pct / 100) AS decimal(38, 10)) AS paybill_whatif,
       CAST(t.paybill * (1 + s.headcount_change_pct / 100) * (1 + s.pay_award_pct / 100) - t.paybill AS decimal(38, 10)) AS paybill_effect
FROM s CROSS JOIN t
ORDER BY s.setting;
