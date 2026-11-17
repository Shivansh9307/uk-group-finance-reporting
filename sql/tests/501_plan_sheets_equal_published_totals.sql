-- test: every Estimates sheet-year and every PESA department-group section loaded equals the sheet's own published total row, within the rounding of the published figures
SELECT family, edition, sheet, section, year_label, line_count, lines_sum, published_total, difference, tolerance, 'lines do not add to the published total' AS problem
FROM audit.plan_sheet_control
WHERE status = 'fail'
UNION ALL
-- every Estimates sheet-year with a plan or outturn figure must have been controlled (27 sheet-years in the 9 workbooks)
SELECT 'estimates', f.edition, r.sheet, '', r.year_label, NULL, NULL, NULL, NULL, NULL, 'sheet-year has no passing control row'
FROM raw.plan_estimates AS r
JOIN raw.plan_source_file AS f ON f.file_id = r.file_id
GROUP BY f.edition, r.sheet, r.year_label
HAVING NOT EXISTS (SELECT 1 FROM audit.plan_sheet_control AS c
                   WHERE c.family = 'estimates' AND c.edition = f.edition AND c.sheet = r.sheet
                     AND c.year_label = r.year_label AND c.status = 'pass')
UNION ALL
SELECT 'estimates', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       'expected 27 passing Estimates sheet-years, found ' + CAST(COUNT(*) AS varchar(5))
FROM audit.plan_sheet_control WHERE family = 'estimates' AND status = 'pass'
HAVING COUNT(*) <> 27;
