-- Independent of the model: the outturn fact by financial year, each line placed in a department twice, once by the
-- department number it was reported under (answered for by the live department with that number, by the Unallocated
-- member U + the number, or, for the one number with neither, by the live department that receives most of it) and once
-- by its current department. The sums over the departments are those of the two placements, and the transfer is the
-- sum of the departments' differences.
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
    JOIN dw.dim_department AS cd ON cd.department_key = f.current_department_key
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
), per_dept AS (
    SELECT COALESCE(c.fy, r.fy) AS fy, COALESCE(c.dep, r.dep) AS dep, c.amt AS cur_amt, r.amt AS rep_amt
    FROM cur AS c FULL JOIN rep AS r ON r.fy = c.fy AND r.dep = c.dep
)
SELECT fy AS [Financial Year],
       CAST((SELECT SUM(amount_delta) FROM fact AS t WHERE t.fy = p.fy) AS decimal(38, 4)) AS total,
       CAST(SUM(cur_amt) AS decimal(38, 4)) AS sum_current,
       CAST(SUM(rep_amt) AS decimal(38, 4)) AS sum_as_reported,
       CAST(SUM(ISNULL(cur_amt, 0) - ISNULL(rep_amt, 0)) AS decimal(38, 4)) AS sum_transfer
FROM per_dept AS p
GROUP BY fy
ORDER BY fy;
