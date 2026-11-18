-- Independent of the model: the lines of dw.current_structure_line marked is_estimated, joined to the outturn fact on
-- organisation version and sub-segment code, by financial year and current department number. The share is the
-- estimated amount over the department's net outturn, in parts per million, missing where the net outturn is zero.
-- A department and year with neither an estimated amount nor a share has no row (the model returns BLANK for both).
WITH fact AS (
    SELECT p.financial_year AS fy, cd.department_number AS dep, f.amount_delta, l.is_estimated
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS p ON p.period_key = f.period_key
    JOIN dw.dim_segment AS sg ON sg.segment_key = f.segment_key
    JOIN dw.current_structure_line AS l ON l.organisation_key = f.organisation_key AND l.sub_segment_code = sg.sub_segment_code
    JOIN dw.dim_department AS cd ON cd.department_key = l.current_department_key
), g AS (
    SELECT fy, dep, SUM(amount_delta) AS total,
           SUM(CASE WHEN is_estimated = 1 THEN amount_delta END) AS estimated
    FROM fact GROUP BY fy, dep
)
SELECT fy AS [Financial Year], dep AS [Department Number],
       CAST(estimated AS decimal(38, 4)) AS estimated,
       CAST(CASE WHEN total <> 0 THEN CAST(ISNULL(estimated, 0) AS decimal(38, 10)) * 1000000 / CAST(total AS decimal(38, 10)) END AS decimal(38, 6)) AS share_ppm
FROM g
WHERE estimated IS NOT NULL OR total <> 0
ORDER BY fy, dep;
