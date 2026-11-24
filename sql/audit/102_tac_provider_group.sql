-- scope: full
-- dw.tac_provider_group: the link of every TAC provider to the central-government group, which is at the level of the
-- Department of Health and Social Care and no finer: the TAC files carry no OSCAR organisation per trust.
--   department_key     the key the department dimension (dw.dim_department) gives the Department of Health and
--                      Social Care, looked up by its name, never typed in
--   department_number  its three-digit department number
--   link_level         'department': the provider is under the department, not under an OSCAR organisation
-- The file sits in the audit layer only because the department dimension (sql/dw/200) is built after the files of
-- sql/dw numbered below 200; it is a warehouse table all the same. The build stops if the department is not found
-- exactly once.

DROP TABLE IF EXISTS dw.tac_provider_group;
GO

CREATE TABLE dw.tac_provider_group (
    provider_key       int           NOT NULL CONSTRAINT pk_dw_tac_provider_group PRIMARY KEY,
    department_key     int           NOT NULL,
    department_number  nvarchar(10)  NOT NULL,
    link_level         varchar(20)   NOT NULL,
    CONSTRAINT fk_dw_tac_provider_group_provider FOREIGN KEY (provider_key) REFERENCES dw.tac_provider (provider_key)
);
GO

IF (SELECT COUNT(*) FROM dw.dim_department
    WHERE department_name = N'Department of Health and Social Care' AND member_type = 'Department' AND is_current = 1) <> 1
    THROW 50000, 'the Department of Health and Social Care is not exactly one current department in dw.dim_department', 1;
GO

INSERT INTO dw.tac_provider_group (provider_key, department_key, department_number, link_level)
SELECT p.provider_key, d.department_key, d.department_number, 'department'
FROM dw.tac_provider AS p
CROSS JOIN (SELECT department_key, department_number FROM dw.dim_department
            WHERE department_name = N'Department of Health and Social Care' AND member_type = 'Department'
              AND is_current = 1) AS d;
GO
