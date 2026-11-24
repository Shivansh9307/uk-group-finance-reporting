-- test: the column the reader keyed as a headline measure has the published header wording for it, read from the label as published and not from the reader's key
-- marker: localdata
-- requires: raw.workforce_value
SELECT TOP (20) measure_key, column_label, COUNT(DISTINCT file_id) AS files
FROM raw.workforce_value
WHERE (measure_key = 'payroll_total_fte'
       AND NOT ((column_label LIKE '%total%' OR column_label LIKE '%yotal%') AND (column_label LIKE '%equivalent%' OR column_label LIKE '%FTE%')
                AND column_label LIKE '%payroll%'))
   OR (measure_key = 'payroll_total_hc'
       AND NOT (column_label LIKE '%total%' AND column_label LIKE '%headcount%' AND column_label LIKE '%payroll%'))
   OR (measure_key = 'cost_payroll_paybill_gbp'
       AND NOT (column_label LIKE '%paybill%' OR column_label LIKE '%total bill%'))
   OR (measure_key = 'cost_grand_total_gbp'
       AND NOT (column_label LIKE '%grand%' OR column_label LIKE '%total%' OR column_label LIKE '%paybill/staffing%'))
   OR (measure_key = 'grand_total_fte'
       AND NOT (column_label LIKE '%grand%' AND (column_label LIKE '%equivalent%' OR column_label LIKE '%FTE%')))
GROUP BY measure_key, column_label;
