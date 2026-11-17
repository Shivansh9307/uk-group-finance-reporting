-- dw.dim_account: one row per economic category code in the in-year data, plus the Unknown member (-1).
--   Attributes are taken from the latest release that reports the code with a non-zero amount.
--   The code 'n/a' (2019-03 to 2021-06) and the code 'NA' (2021-09 onwards) are one thing under two
--   spellings and never appear in the same release, so both are the member 'NA'; source_codes says so.
--   economic_budget   an attribute of the category, not part of the fact key. Its relabel from
--                     'OTHER NON-BUDGET' to 'NA' for the NA category in December 2022 therefore changes
--                     nothing in the fact.
--   pesa_economic_group / _code   the group as published; the long name exists only in the 2019 layout
--                     (to June 2021), so the name is read from any release that has it.
--   flow              Expenditure | Income | Not applicable. The authored map (authored/account_flow.csv)
--                     where it lists the code, otherwise the digit rule: a final digit 1 is Expenditure and
--                     a final digit 2 is Income. A code with any other final digit and no authored row stops
--                     the build (the insert fails on a NULL flow). Sign alone does not decide it: 125 of 128 categories carry both signs.
--   flow_basis        'authored' or 'digit rule'

DROP TABLE IF EXISTS dw.dim_account;
GO

CREATE TABLE dw.dim_account (
    account_key              int           NOT NULL CONSTRAINT pk_dw_dim_account PRIMARY KEY,
    economic_category_code   nvarchar(50)  NOT NULL,
    economic_category_name   nvarchar(400) NOT NULL,
    economic_category_label  nvarchar(460) NOT NULL,
    pesa_economic_group_code nvarchar(400) NOT NULL,
    pesa_economic_group      nvarchar(400) NOT NULL,
    economic_budget          nvarchar(100) NOT NULL,
    flow                     varchar(20)   NOT NULL,
    flow_basis               varchar(20)   NOT NULL,
    source_codes             nvarchar(100) NOT NULL,
    first_release            varchar(7)    NOT NULL,
    last_release             varchar(7)    NOT NULL,
    CONSTRAINT uq_dw_dim_account_code UNIQUE (economic_category_code)
);
GO

INSERT INTO dw.dim_account
    (account_key, economic_category_code, economic_category_name, economic_category_label, pesa_economic_group_code,
     pesa_economic_group, economic_budget, flow, flow_basis, source_codes, first_release, last_release)
VALUES (-1, N'UNK', N'Unknown', N'UNK Unknown', N'Unknown', N'Unknown', N'Unknown', 'Not applicable', 'authored',
        N'UNK', '2019-03', '2019-03');
GO

WITH s AS (
    SELECT CASE WHEN economic_category_code = 'n/a' THEN 'NA' ELSE economic_category_code END AS code,
           economic_category_code AS source_code, release, economic_budget_code, pesa_economic_group_code
    FROM stg.inyear_snapshot
    GROUP BY CASE WHEN economic_category_code = 'n/a' THEN 'NA' ELSE economic_category_code END,
             economic_category_code, release, economic_budget_code, pesa_economic_group_code
), codes AS (
    SELECT code, source_code, MIN(release) AS first_release, MAX(release) AS last_release FROM s GROUP BY code, source_code
), span AS (
    SELECT code, MIN(first_release) AS first_release, MAX(last_release) AS last_release,
           STRING_AGG(source_code, ' | ') WITHIN GROUP (ORDER BY source_code) AS source_codes
    FROM codes
    GROUP BY code
), latest AS (
    SELECT s.code, s.release, MAX(s.economic_budget_code) AS economic_budget_code,
           MIN(s.economic_budget_code) AS economic_budget_code_min,
           MAX(s.pesa_economic_group_code) AS pesa_economic_group_code
    FROM s
    JOIN span ON span.code = s.code AND span.last_release = s.release
    GROUP BY s.code, s.release
), nm AS (
    SELECT l.code, MAX(r.economic_category_name) AS economic_category_name
    FROM latest AS l
    JOIN raw.oscar_inyear AS r
      ON r.release = l.release
     AND CASE WHEN r.economic_category_code = 'n/a' THEN 'NA' ELSE r.economic_category_code END = l.code
    GROUP BY l.code
), grp AS (
    SELECT g.pesa_economic_group_code, g.pesa_economic_group_name
    FROM (
        SELECT r.pesa_economic_group_code, r.pesa_economic_group_name,
               ROW_NUMBER() OVER (PARTITION BY r.pesa_economic_group_code ORDER BY r.release DESC, r.pesa_economic_group_name) AS rn
        FROM raw.oscar_inyear AS r
        WHERE r.pesa_economic_group_name <> ''
        GROUP BY r.pesa_economic_group_code, r.pesa_economic_group_name, r.release
    ) AS g
    WHERE g.rn = 1
)
INSERT INTO dw.dim_account
    (account_key, economic_category_code, economic_category_name, economic_category_label, pesa_economic_group_code,
     pesa_economic_group, economic_budget, flow, flow_basis, source_codes, first_release, last_release)
SELECT ROW_NUMBER() OVER (ORDER BY l.code),
       l.code, nm.economic_category_name, l.code + N' ' + nm.economic_category_name,
       l.pesa_economic_group_code, ISNULL(grp.pesa_economic_group_name, l.pesa_economic_group_code),
       l.economic_budget_code,
       CAST(COALESCE(af.flow,
                     CASE RIGHT(l.code, 1) WHEN '1' THEN 'Expenditure' WHEN '2' THEN 'Income' END) AS varchar(20)),
       CAST(CASE WHEN af.flow IS NOT NULL THEN 'authored' ELSE 'digit rule' END AS varchar(20)),
       span.source_codes, span.first_release, span.last_release
FROM latest AS l
JOIN span ON span.code = l.code
JOIN nm ON nm.code = l.code
LEFT JOIN grp ON grp.pesa_economic_group_code = l.pesa_economic_group_code
LEFT JOIN stg.account_flow AS af ON af.economic_category_code = l.code;
GO
