-- dw.dim_control_budget: one row per control budget detail code, plus the Unknown member (-1).
--   control_budget            DEL | AME | Non-budget. The published control budget changes its spelling in
--                             December 2022 ('DEL' becomes 'TOTAL DEL'); the leading 'TOTAL ' is removed.
--                             It is one value per detail code in all 31 releases (a build guard and a test).
--   control_budget_detail     my display name for the detail code
--   published_labels          the control budget values as published, joined with ' | '

DROP TABLE IF EXISTS dw.dim_control_budget;
GO

CREATE TABLE dw.dim_control_budget (
    control_budget_key          int           NOT NULL CONSTRAINT pk_dw_dim_control_budget PRIMARY KEY,
    control_budget_detail_code  nvarchar(100) NOT NULL,
    control_budget_detail       nvarchar(100) NOT NULL,
    control_budget              varchar(20)   NOT NULL,
    published_labels            nvarchar(300) NOT NULL,
    first_release               varchar(7)    NOT NULL,
    last_release                varchar(7)    NOT NULL,
    CONSTRAINT uq_dw_dim_control_budget_code UNIQUE (control_budget_detail_code)
);
GO

INSERT INTO dw.dim_control_budget
    (control_budget_key, control_budget_detail_code, control_budget_detail, control_budget, published_labels,
     first_release, last_release)
VALUES (-1, N'UNK', N'Unknown', 'Unknown', N'Unknown', '2019-03', '2019-03');
GO

WITH p AS (
    SELECT DISTINCT control_budget_detail_code, control_budget_code, release FROM stg.inyear_snapshot
), n AS (
    SELECT control_budget_detail_code, control_budget_code, release,
           CASE WHEN control_budget_code LIKE 'TOTAL %' THEN SUBSTRING(control_budget_code, 7, 100) ELSE control_budget_code END AS cb
    FROM p
)
INSERT INTO dw.dim_control_budget
    (control_budget_key, control_budget_detail_code, control_budget_detail, control_budget, published_labels,
     first_release, last_release)
SELECT ROW_NUMBER() OVER (ORDER BY g.control_budget_detail_code),
       g.control_budget_detail_code,
       CASE g.control_budget_detail_code
            WHEN 'DEL ADMIN' THEN N'DEL admin' WHEN 'DEL PROG' THEN N'DEL programme'
            WHEN 'DEPT AME' THEN N'Departmental AME' WHEN 'NON-DEPT AME' THEN N'Non-departmental AME'
            WHEN 'NON-BUDGET' THEN N'Non-budget' ELSE g.control_budget_detail_code END,
       CASE MIN(g.cb) WHEN 'DEL' THEN 'DEL' WHEN 'AME' THEN 'AME' WHEN 'NON-BUDGET' THEN 'Non-budget' END,
       STRING_AGG(CAST(g.control_budget_code AS nvarchar(100)), ' | ') WITHIN GROUP (ORDER BY g.first_release, g.control_budget_code),
       MIN(g.first_release), MAX(g.last_release)
FROM (
    SELECT control_budget_detail_code, control_budget_code, MIN(cb) AS cb, MIN(release) AS first_release, MAX(release) AS last_release
    FROM n
    GROUP BY control_budget_detail_code, control_budget_code
) AS g
GROUP BY g.control_budget_detail_code;
GO

IF EXISTS (SELECT 1 FROM dw.dim_control_budget WHERE control_budget_key > 0 AND control_budget IS NULL)
    THROW 50306, 'a control budget value is not DEL, AME or NON-BUDGET after removing the TOTAL prefix', 1;
GO
IF EXISTS (
    SELECT 1 FROM (SELECT DISTINCT control_budget_detail_code,
                          CASE WHEN control_budget_code LIKE 'TOTAL %' THEN SUBSTRING(control_budget_code, 7, 100) ELSE control_budget_code END AS cb
                   FROM stg.inyear_snapshot) AS d
    GROUP BY control_budget_detail_code HAVING COUNT(*) > 1
)
    THROW 50307, 'a control budget detail code has more than one normalised control budget', 1;
GO
