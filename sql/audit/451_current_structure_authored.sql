-- audit.current_structure_authored: what each row of authored/current_structure_map.csv does.
--   lines_matched   (organisation version, sub-segment) pairs that the row's key and sub-segment cover
--   lines_decided   of those, the pairs the row decides (a line row always decides its pairs; an
--                   organisation row only the pairs no code or name rule reaches)
--   lines_changed   of the decided pairs, those where the rules alone would have chosen another department
--   rule_department_number   the department the rules alone choose for the decided pairs; blank where no
--                   rule gives a department, 'several' where the pairs differ
--   gross_amount    the size of the decided lines: for each financial year (year-end release) the absolute value
--                   of the line's total, summed over the years (GBP thousands)

DROP TABLE IF EXISTS audit.current_structure_authored;
GO

CREATE TABLE audit.current_structure_authored (
    authored_row               int           NOT NULL CONSTRAINT pk_audit_current_structure_authored PRIMARY KEY,
    durable_key                nvarchar(30)  NOT NULL,
    sub_segment_code           nvarchar(50)  NULL,
    decision                   nvarchar(200) NOT NULL,
    review_set                 nvarchar(50)  NULL,
    is_estimated               bit           NOT NULL,
    current_department_number  nvarchar(10)  NOT NULL,
    lines_matched              int           NOT NULL,
    lines_decided              int           NOT NULL,
    lines_changed              int           NOT NULL,
    rule_department_number     nvarchar(10)  NOT NULL,
    gross_amount               decimal(19,4) NOT NULL
);
GO

WITH ye AS (
    SELECT release, financial_year FROM stg.release WHERE highest_period = 12
), per_year AS (
    SELECT ye.financial_year, m.organisation_key, s.sub_segment_code, SUM(s.amount) AS net_amount
    FROM ye
    JOIN stg.inyear_snapshot AS s ON s.release = ye.release AND s.financial_year = ye.financial_year
    JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
    GROUP BY ye.financial_year, m.organisation_key, s.sub_segment_code
), gross AS (
    SELECT organisation_key, sub_segment_code, SUM(ABS(net_amount)) AS gross_amount
    FROM per_year
    GROUP BY organisation_key, sub_segment_code
), matched AS (
    SELECT a.authored_row, l.organisation_key, l.sub_segment_code,
           CASE WHEN l.authored_row = a.authored_row THEN 1 ELSE 0 END AS decided,
           CASE WHEN l.authored_row = a.authored_row AND l.rule_department_key IS NOT NULL
                 AND l.rule_department_key <> l.current_department_key THEN 1 ELSE 0 END AS changed,
           CASE WHEN l.authored_row = a.authored_row THEN ISNULL(rd.department_number, N'') END AS rule_number,
           ISNULL(g.gross_amount, 0) AS gross_amount
    FROM stg.current_structure_authored AS a
    JOIN dw.current_structure_line AS l
      ON l.durable_key = a.durable_key AND (a.sub_segment_code IS NULL OR l.sub_segment_code = a.sub_segment_code)
    LEFT JOIN dw.dim_department AS rd ON rd.department_key = l.rule_department_key
    LEFT JOIN gross AS g ON g.organisation_key = l.organisation_key AND g.sub_segment_code = l.sub_segment_code
)
INSERT INTO audit.current_structure_authored
SELECT a.authored_row, a.durable_key, a.sub_segment_code, a.decision, a.review_set, a.is_estimated, a.current_department_number,
       COUNT(m.organisation_key), ISNULL(SUM(m.decided), 0), ISNULL(SUM(m.changed), 0),
       CASE WHEN COUNT(DISTINCT m.rule_number) > 1 THEN N'several' ELSE ISNULL(MIN(m.rule_number), N'') END,
       CAST(ISNULL(SUM(CASE WHEN m.decided = 1 THEN m.gross_amount END), 0) AS decimal(19,4))
FROM stg.current_structure_authored AS a
LEFT JOIN matched AS m ON m.authored_row = a.authored_row
GROUP BY a.authored_row, a.durable_key, a.sub_segment_code, a.decision, a.review_set, a.is_estimated, a.current_department_number;
GO
