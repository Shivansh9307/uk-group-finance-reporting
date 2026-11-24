-- scope: full
-- stg.tac_template_line: the statement sheets of the six illustrative forms, typed. A row with no sub code is
-- a heading of the form. The data files carry codes and no text; the line text and the expected sign come
-- from here.

DROP TABLE IF EXISTS stg.tac_template_line;
GO

CREATE TABLE stg.tac_template_line (
    file_id        int           NOT NULL,
    release        varchar(7)    NOT NULL,
    statement      varchar(4)    NOT NULL,
    table_id       tinyint       NOT NULL,
    form_row       int           NOT NULL,
    label          nvarchar(400) NOT NULL,
    expected_sign  varchar(5)    NOT NULL,
    sub_code       varchar(20)   NOT NULL,
    is_heading     bit           NOT NULL,
    CONSTRAINT pk_stg_tac_template_line PRIMARY KEY (file_id, statement, form_row)
);
GO

INSERT INTO stg.tac_template_line
    (file_id, release, statement, table_id, form_row, label, expected_sign, sub_code, is_heading)
SELECT t.file_id, f.release,
       CASE LEFT(t.worksheet_name, 5) WHEN 'TAC02' THEN 'SoCI' WHEN 'TAC03' THEN 'SoFP' WHEN 'TAC05' THEN 'SoCF' END,
       CAST(CASE WHEN t.table_id = '' THEN '1' ELSE t.table_id END AS tinyint), t.source_row,
       LTRIM(RTRIM(REPLACE(t.label, CHAR(10), N' '))), t.expected_sign, t.sub_code,
       CAST(CASE WHEN t.sub_code = '' THEN 1 ELSE 0 END AS bit)
FROM raw.tac_template_line AS t
JOIN raw.tac_file AS f ON f.file_id = t.file_id;
GO
