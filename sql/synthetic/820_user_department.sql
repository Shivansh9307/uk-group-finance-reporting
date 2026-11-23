-- phase: pre
-- synthetic.user_department: invented users and the departments of the current structure each may see.
-- SYNTHETIC data, loaded from synthetic/user_department.csv by the synthetic load stage. It holds no amount. It is
-- read by two views for the model's row-level security (dw.v_model_user_department and dw.v_model_user_plan_group) and
-- by nothing else; sql/tests/820 and pipeline/tests/test_register.py check that no real fact or total reads it.
--   user_principal_name  an address in the reserved domain example.org, so it can never be a real person
--   department_number    the three-digit OSCAR department number of a department of the current structure,
--                        never the name; the build of the views stops if the number is not a live department
--   data_class           always 'synthetic'
-- The table is created here (not by the loader) so that the types and checks are in the schema; the loader only
-- empties it and writes the file's rows. A change to the shape needs `ukfr build --recreate`.

IF OBJECT_ID(N'synthetic.user_department') IS NULL
BEGIN
    CREATE TABLE synthetic.user_department (
        _load_order          int            NOT NULL CONSTRAINT pk_synthetic_user_department PRIMARY KEY,
        user_principal_name  nvarchar(200)  NOT NULL,
        department_number    nvarchar(10)   NOT NULL,
        persona              nvarchar(200)  NOT NULL,
        data_class           varchar(20)    NOT NULL,
        note                 nvarchar(1000) NOT NULL,
        CONSTRAINT ck_synthetic_user_department_class CHECK (data_class = 'synthetic'),
        CONSTRAINT ck_synthetic_user_department_domain CHECK (user_principal_name LIKE N'%@example.org'),
        CONSTRAINT ck_synthetic_user_department_number CHECK (department_number LIKE N'[0-9][0-9][0-9]'),
        CONSTRAINT uq_synthetic_user_department UNIQUE (user_principal_name, department_number)
    );
END
GO

IF EXISTS (SELECT 1 FROM sys.extended_properties
           WHERE class = 1 AND major_id = OBJECT_ID(N'synthetic.user_department') AND minor_id = 0 AND name = N'MS_Description')
    EXEC sys.sp_dropextendedproperty @name = N'MS_Description',
        @level0type = N'SCHEMA', @level0name = N'synthetic', @level1type = N'TABLE', @level1name = N'user_department';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'SYNTHETIC data, loaded from synthetic/user_department.csv: invented users (example.org addresses) and the departments of the current structure each may see, for the model''s row-level security. It holds no amount and is never part of a real total.',
    @level0type = N'SCHEMA', @level0name = N'synthetic', @level1type = N'TABLE', @level1name = N'user_department';
GO
