-- scope: full
-- stg.pss_outturn: the Public Spending Statistics database, typed. One row per source row of the Database
-- sheet (nothing is dropped, zero amounts included), amounts in GBP thousands, spending positive.
--   basis_rdel_excl_depreciation = DEL, resource, and the economic ringfence is not RINGFENCED
--     RESOURCE. The PSS metadata describes its resource DEL as excluding depreciation, and the
--     ringfenced resource lines are almost empty in the file, so this flag marks the rows the
--     comparison with OSCAR counts as "resource DEL excluding depreciation".
--   The PSS leaves out the security and intelligence agencies and the operational costs of military
--   operations, to line up with OSCAR's published data; it has no organisation and no month.

DROP TABLE IF EXISTS stg.pss_outturn;
GO

CREATE TABLE stg.pss_outturn (
    file_id                       int            NOT NULL,
    source_row                    int            NOT NULL,
    financial_year                varchar(7)     NOT NULL,   -- '2023-24'
    economic_budget_code          nvarchar(50)   NOT NULL,   -- RESOURCE | CAPITAL
    economic_ringfence_code       nvarchar(100)  NOT NULL,
    control_budget_code           nvarchar(50)   NOT NULL,   -- DEL | AME
    control_budget_detail_code    nvarchar(50)   NOT NULL,   -- DEL ADMIN | DEL PROG | DEPT AME
    sr_group_name                 nvarchar(200)  NOT NULL,   -- Spending Review group, by name (the PSS has no code)
    segment_code                  nvarchar(50)   NOT NULL,
    segment_name                  nvarchar(1000) NOT NULL,
    pesa_economic_group_name      nvarchar(400)  NOT NULL,
    amount                        decimal(19,4)  NOT NULL,   -- GBP thousands
    basis_rdel_excl_depreciation  bit            NOT NULL,
    CONSTRAINT pk_stg_pss_outturn PRIMARY KEY CLUSTERED (file_id, source_row)
);
GO

INSERT INTO stg.pss_outturn WITH (TABLOCK)
SELECT p.file_id, p.source_row, p.[year], p.economic_budget_code, p.economic_ringfence_code, p.control_budget_code,
       p.control_budget_detail_code, p.sr_group_long_name, p.segment_code, p.segment_long_name,
       p.pesa_economic_group_long_name, CAST(p.amount AS decimal(19,4)),
       CAST(CASE WHEN p.control_budget_code = 'DEL' AND p.economic_budget_code = 'RESOURCE'
                  AND p.economic_ringfence_code <> 'RINGFENCED RESOURCE' THEN 1 ELSE 0 END AS bit)
FROM raw.pss AS p
ORDER BY p.file_id, p.source_row;
GO
