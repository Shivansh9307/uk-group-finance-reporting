-- Independent of the model: as test 764, by the release that made the delta rows. A release's rows change only that
-- release's financial year, so the totals are those of its own deltas.
WITH live AS (
    SELECT d.department_key, d.department_number, d.member_type
    FROM dw.dim_department AS d JOIN dw.current_structure_department AS c ON c.department_key = d.department_key
    WHERE c.is_live = 1
), fact AS (
    SELECT f.release_key AS rk, rd.department_number AS rep_no, cd.department_number AS cur_no, f.amount_delta
    FROM dw.fact_outturn AS f
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
    SELECT rk, cur_no AS dep, SUM(amount_delta) AS amt FROM fact GROUP BY rk, cur_no
), rep AS (
    SELECT f.rk, a.ans_no AS dep, SUM(f.amount_delta) AS amt FROM fact AS f JOIN answer AS a ON a.rep_no = f.rep_no GROUP BY f.rk, a.ans_no
), per_dept AS (
    SELECT COALESCE(c.rk, r.rk) AS rk, COALESCE(c.dep, r.dep) AS dep, c.amt AS cur_amt, r.amt AS rep_amt
    FROM cur AS c FULL JOIN rep AS r ON r.rk = c.rk AND r.dep = c.dep
)
SELECT rl.label AS [Release Label],
       CAST((SELECT SUM(amount_delta) FROM fact AS t WHERE t.rk = p.rk) AS decimal(38, 4)) AS total,
       CAST(SUM(cur_amt) AS decimal(38, 4)) AS sum_current,
       CAST(SUM(rep_amt) AS decimal(38, 4)) AS sum_as_reported,
       CAST(SUM(ISNULL(cur_amt, 0) - ISNULL(rep_amt, 0)) AS decimal(38, 4)) AS sum_transfer
FROM per_dept AS p
JOIN dw.dim_release AS rl ON rl.release_key = p.rk
GROUP BY rl.label, p.rk
ORDER BY rl.label;
