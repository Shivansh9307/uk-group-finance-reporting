-- Independent of the model: the current department of each line from dw.current_structure_line (not from the fact's
-- own key), and the department that answers for each reported number from the three rules written out here (own
-- number, the Unallocated member U + the number, the live department that receives most of the number). The transfer
-- is current less as reported, a missing side counting as zero, and is missing only where both are.
WITH live AS (
    SELECT d.department_key, d.department_number, d.member_type
    FROM dw.dim_department AS d JOIN dw.current_structure_department AS c ON c.department_key = d.department_key
    WHERE c.is_live = 1
), fact AS (
    SELECT p.financial_year AS fy, rd.department_number AS rep_no, cd.department_number AS cur_no, f.amount_delta
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS p ON p.period_key = f.period_key
    JOIN dw.dim_organisation AS o ON o.organisation_key = f.organisation_key
    JOIN dw.dim_department AS rd ON rd.department_key = o.department_key
    JOIN dw.dim_segment AS sg ON sg.segment_key = f.segment_key
    JOIN dw.current_structure_line AS l ON l.organisation_key = f.organisation_key AND l.sub_segment_code = sg.sub_segment_code
    JOIN dw.dim_department AS cd ON cd.department_key = l.current_department_key
), answer AS (
    SELECT n.rep_no,
           COALESCE((SELECT TOP 1 l.department_number FROM live AS l WHERE l.member_type = 'Department' AND l.department_number = n.rep_no),
                    (SELECT TOP 1 l.department_number FROM live AS l WHERE l.member_type = 'Unallocated' AND l.department_number = N'U' + n.rep_no),
                    (SELECT TOP 1 x.cur_no FROM fact AS x WHERE x.rep_no = n.rep_no GROUP BY x.cur_no ORDER BY ABS(SUM(x.amount_delta)) DESC, x.cur_no)) AS ans_no
    FROM (SELECT DISTINCT rep_no FROM fact) AS n
), cur AS (
    SELECT fy, cur_no AS dep, SUM(amount_delta) AS amt FROM fact GROUP BY fy, cur_no
), rep AS (
    SELECT f.fy, a.ans_no AS dep, SUM(f.amount_delta) AS amt FROM fact AS f JOIN answer AS a ON a.rep_no = f.rep_no GROUP BY f.fy, a.ans_no
)
SELECT COALESCE(c.fy, r.fy) AS [Financial Year], COALESCE(c.dep, r.dep) AS [Department Number],
       CAST(c.amt AS decimal(38, 4)) AS current_structure,
       CAST(r.amt AS decimal(38, 4)) AS as_reported,
       CAST(ISNULL(c.amt, 0) - ISNULL(r.amt, 0) AS decimal(38, 4)) AS [transfer]
FROM cur AS c
FULL JOIN rep AS r ON r.fy = c.fy AND r.dep = c.dep
ORDER BY COALESCE(c.fy, r.fy), COALESCE(c.dep, r.dep);
