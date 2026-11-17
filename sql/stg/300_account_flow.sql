-- authored/account_flow.csv, typed.
--   economic_category_code   a code whose income / expenditure value I decided by hand
--   flow                     Expenditure | Income | Not applicable
-- The codes of dw.dim_account that are not listed here take the digit rule: a final digit 1 is
-- Expenditure, a final digit 2 is Income (dw/305_dim_account.sql). A flow outside the three values, a
-- code listed twice, or a code that does not exist in the in-year data stops the build.

DROP TABLE IF EXISTS stg.account_flow;
GO

IF EXISTS (SELECT 1 FROM authored.account_flow WHERE LTRIM(RTRIM(flow)) NOT IN ('Expenditure', 'Income', 'Not applicable'))
    THROW 50300, 'authored/account_flow.csv has a flow that is not Expenditure, Income or Not applicable', 1;
GO
IF EXISTS (SELECT 1 FROM authored.account_flow GROUP BY LTRIM(RTRIM(economic_category_code)) HAVING COUNT(*) > 1)
    THROW 50301, 'authored/account_flow.csv lists an economic category code twice', 1;
GO
IF EXISTS (
    SELECT 1 FROM authored.account_flow AS a
    WHERE NOT EXISTS (SELECT 1 FROM stg.inyear_snapshot AS s
                      WHERE s.economic_category_code = LTRIM(RTRIM(a.economic_category_code))
                         OR (s.economic_category_code = 'n/a' AND LTRIM(RTRIM(a.economic_category_code)) = 'NA'))
)
    THROW 50302, 'authored/account_flow.csv names an economic category code that is not in the in-year data', 1;
GO

CREATE TABLE stg.account_flow (
    flow_id                 int           NOT NULL CONSTRAINT pk_stg_account_flow PRIMARY KEY,   -- _load_order
    economic_category_code  nvarchar(50)  NOT NULL,
    flow                    varchar(20)   NOT NULL,
    evidence                nvarchar(max) NOT NULL,
    note                    nvarchar(max) NOT NULL
);
GO

INSERT INTO stg.account_flow (flow_id, economic_category_code, flow, evidence, note)
SELECT a._load_order, LTRIM(RTRIM(a.economic_category_code)), LTRIM(RTRIM(a.flow)), a.evidence, a.note
FROM authored.account_flow AS a;
GO
