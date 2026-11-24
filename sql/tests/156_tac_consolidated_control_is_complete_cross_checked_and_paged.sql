-- test: the hand-keyed consolidated values are complete and agree with themselves: eight printed lines in each of the six years, each in exactly one control line, with a page of the printed statement and of the PDF; the value of year Y equals the comparative column of the report of year Y+1 wherever that report exists (no restatement was found); the four printed totals add up to the printed total assets employed to within GBP 1 million; the printed lines are in GBP million, whole numbers, with the sign of the printed statement
-- marker: localdata
-- requires: dw.tac_consolidated_control, dw.tac_control_line
SELECT release AS what, 'a year does not have the eight printed lines' AS problem
FROM dw.tac_consolidated_control GROUP BY release HAVING COUNT(*) <> 8
UNION ALL
SELECT 'years', 'the control covers other than six years'
WHERE (SELECT COUNT(DISTINCT release) FROM dw.tac_consolidated_control) <> 6
UNION ALL
SELECT c.release + ' ' + c.printed_line, 'no page, or a page of 0 or less'
FROM dw.tac_consolidated_control AS c WHERE c.pdf_page <= 0 OR c.printed_page <= 0 OR c.pdf_page < c.printed_page
UNION ALL
SELECT c.release + ' ' + c.printed_line, 'value differs from the comparative column of the next report'
FROM dw.tac_consolidated_control AS c
WHERE c.next_report_comparative_gbp_million IS NOT NULL AND c.next_report_comparative_gbp_million <> c.amount_gbp_million
UNION ALL
SELECT c.release + ' ' + c.printed_line, 'no comparative column, and the year has a later report'
FROM dw.tac_consolidated_control AS c
WHERE c.next_report_comparative_gbp_million IS NULL AND c.release < (SELECT MAX(release) FROM dw.tac_consolidated_control)
UNION ALL
SELECT c.release + ' ' + c.printed_line, 'value is not a whole number of millions, or its amount in thousands is not 1,000 times it'
FROM dw.tac_consolidated_control AS c
WHERE c.amount_gbp_million <> ROUND(c.amount_gbp_million, 0) OR c.amount <> c.amount_gbp_million * 1000
UNION ALL
SELECT c.release + ' ' + c.printed_line, 'sign is not the printed sign (income, assets and cash positive; expenses and liabilities negative)'
FROM dw.tac_consolidated_control AS c
WHERE (c.printed_line IN ('TOTAL_OPERATING_INCOME', 'TOTAL_NON_CURRENT_ASSETS', 'TOTAL_CURRENT_ASSETS', 'CASH_AND_CASH_EQUIVALENTS') AND c.amount_gbp_million <= 0)
   OR (c.printed_line IN ('OPERATING_EXPENSES', 'TOTAL_CURRENT_LIABILITIES', 'TOTAL_NON_CURRENT_LIABILITIES') AND c.amount_gbp_million >= 0)
UNION ALL
SELECT release, 'printed totals do not add up to the printed total assets employed'
FROM dw.tac_consolidated_control
GROUP BY release
HAVING ABS(SUM(CASE WHEN printed_line IN ('TOTAL_NON_CURRENT_ASSETS', 'TOTAL_CURRENT_ASSETS', 'TOTAL_CURRENT_LIABILITIES', 'TOTAL_NON_CURRENT_LIABILITIES') THEN amount_gbp_million END)
           - MAX(CASE WHEN printed_line = 'TOTAL_ASSETS_EMPLOYED' THEN amount_gbp_million END)) > 1
UNION ALL
SELECT cl.control_line, 'control line without a printed line'
FROM dw.tac_control_line AS cl
WHERE NOT EXISTS (SELECT 1 FROM dw.tac_consolidated_control AS c WHERE c.control_line_key = cl.control_line_key)
UNION ALL
SELECT 'authored', 'the authored file has other than 48 printed values or 6 control lines'
WHERE (SELECT COUNT(*) FROM stg.tac_consolidated_control) <> 48 OR (SELECT COUNT(*) FROM stg.tac_control_line) <> 6;
