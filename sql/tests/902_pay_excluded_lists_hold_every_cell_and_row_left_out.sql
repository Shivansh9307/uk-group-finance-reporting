-- test: audit.pay_excluded_cell holds exactly the cells that are not valid (375) with their reason, audit.pay_bridge_not_bridged exactly the rows of the bridge that are left out (2,256), no excluded cell is in the bridge as a current or prior value of a bridged row, and the paybill of dw.workforce_month is accounted for: the paybill of the valid cells plus the paybill of the excluded cells is the paybill of every cell
-- marker: localdata
-- requires: audit.pay_excluded_cell, audit.pay_bridge_not_bridged, dw.workforce_month
SELECT 'excluded cells' AS what, CONCAT('expected 375, found ', COUNT(*)) AS problem FROM audit.pay_excluded_cell HAVING COUNT(*) <> 375
UNION ALL
SELECT 'not bridged rows', CONCAT('expected 2256, found ', COUNT(*)) FROM audit.pay_bridge_not_bridged HAVING COUNT(*) <> 2256
UNION ALL
SELECT CONCAT('excluded cell ', x.durable_key, ' ', x.month_start), 'an excluded cell is a bridged current or prior value'
FROM audit.pay_excluded_cell AS x
JOIN dw.v_model_pay_bridge AS b ON b.durable_key = x.durable_key AND b.bridge_class IN ('continuing', 'entry', 'exit')
 AND ((b.month_start = x.month_start AND b.pay_cur IS NOT NULL)
   OR (b.month_start = DATEADD(YEAR, 1, x.month_start) AND b.pay_prior IS NOT NULL))
UNION ALL
SELECT 'paybill', 'valid plus excluded paybill is not the paybill of dw.workforce_month'
FROM (SELECT (SELECT SUM(paybill) FROM dw.v_pay_cell WHERE cell_status = 'valid')
             + (SELECT SUM(paybill) FROM audit.pay_excluded_cell) AS parts,
             (SELECT SUM(value) FROM dw.workforce_month WHERE measure_key = 'payroll_paybill_gbp') AS whole) AS t
WHERE t.parts <> t.whole;
