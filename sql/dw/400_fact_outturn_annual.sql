-- scope: full
-- dw.fact_outturn_annual: annual restated outturn from the BUD workbooks, GBP thousands, spending positive.
--   Grain: vintage x financial year x organisation x economic category x control budget detail (L0) x
--   economic budget x economic ringfence x TYPE layer. Sub-segments, chart-of-accounts codes and months
--   are summed away (the BUD has annual figures only: every row is period P00).
--   Every TYPE layer is included: the layers stack as reasons for change and are not alternatives.
--   Rows with STATUS_CODE = 'Closed' are excluded: each repeats a row held under another status. Their
--   count and amount are recorded per workbook in audit.bud_file_control. Submitted and Locked rows stay.
--   Keys stay as source codes; the model layer joins them to its dimensions.
--   control_budget_code is the control budget level 1 (DEL, AME, NON-BUDGET); it follows from the
--   control budget detail (tested), carried so that a DEL filter needs no lookup.
--   Flags:
--     is_latest_vintage              the newest annual release loaded
--     is_dept_group_scotland         the organisation sits in the Scottish Government department group.
--                                    The Public Spending Statistics take the block grant adjustment off
--                                    Scotland's resource DEL and OSCAR does not, so comparisons with
--                                    them leave this group out of resource DEL or add the adjustment.
--     basis_rdel_excl_depreciation   resource DEL excluding the RINGFENCED economic ringfence (the
--                                    depreciation and other non-cash budget), the basis plans use:
--                                    control budget DEL, economic budget RESOURCE, ringfence <> 'RINGFENCED'.
--   source_rows = BUD rows summed into the fact row (lineage).

DROP TABLE IF EXISTS dw.fact_outturn_annual;
GO

CREATE TABLE dw.fact_outturn_annual (
    vintage                        varchar(7)    NOT NULL,   -- annual release: 2023-11, 2024-11, 2025-11
    financial_year                 varchar(7)    NOT NULL,   -- '2022-23'
    organisation_code              nvarchar(20)  NOT NULL,
    economic_category_code         nvarchar(20)  NOT NULL,
    control_budget_detail_code     nvarchar(20)  NOT NULL,   -- DEL ADMIN | DEL PROG | DEPT AME | NON-DEPT AME | NON-BUDGET
    economic_budget_code           nvarchar(100) NOT NULL,   -- RESOURCE | CAPITAL | OTHER NON-BUDGET | n/a | ...
    economic_ringfence_code        nvarchar(100) NOT NULL,   -- RINGFENCED | NON-RINGFENCED | GENERAL CAPITAL | ...
    type_code                      nvarchar(50)  NOT NULL,   -- the TYPE layer
    control_budget_code            nvarchar(20)  NOT NULL,   -- DEL | AME | NON-BUDGET
    amount                         decimal(19,4) NOT NULL,   -- GBP thousands
    source_rows                    int           NOT NULL,
    is_latest_vintage              bit           NOT NULL,
    is_dept_group_scotland         bit           NOT NULL,
    basis_rdel_excl_depreciation   bit           NOT NULL,
    CONSTRAINT pk_dw_fact_outturn_annual PRIMARY KEY CLUSTERED
        (vintage, financial_year, organisation_code, economic_category_code, control_budget_detail_code,
         economic_budget_code, economic_ringfence_code, type_code)
);
GO

WITH latest AS (
    SELECT MAX(vintage) AS vintage FROM raw.oscar_bud_file WHERE load_status = 'loaded'
)
INSERT INTO dw.fact_outturn_annual WITH (TABLOCK)
SELECT r.vintage,
       LEFT(r.year_no, 4) + '-' + RIGHT(r.year_no, 2) AS financial_year,
       r.organisation_code,
       r.economic_category_code,
       r.control_budget_l0_long_name,
       r.economic_budget_code,
       r.economic_ringfence_code,
       r.type_code,
       MAX(r.control_budget_l1_long_name),
       CAST(SUM(r.amount) AS decimal(19,4)),
       COUNT(*),
       CAST(CASE WHEN r.vintage = (SELECT vintage FROM latest) THEN 1 ELSE 0 END AS bit),
       CAST(CASE WHEN MAX(r.department_group_code) = 'SCT075.GROUP' THEN 1 ELSE 0 END AS bit),
       CAST(CASE WHEN MAX(r.control_budget_l1_long_name) = 'DEL' AND r.economic_budget_code = 'RESOURCE'
                  AND r.economic_ringfence_code <> 'RINGFENCED' THEN 1 ELSE 0 END AS bit)
FROM raw.oscar_bud AS r
WHERE r.status_code <> 'Closed'
GROUP BY r.vintage, LEFT(r.year_no, 4) + '-' + RIGHT(r.year_no, 2), r.organisation_code, r.economic_category_code,
         r.control_budget_l0_long_name, r.economic_budget_code, r.economic_ringfence_code, r.type_code
ORDER BY r.vintage, LEFT(r.year_no, 4) + '-' + RIGHT(r.year_no, 2), r.organisation_code, r.economic_category_code,
         r.control_budget_l0_long_name, r.economic_budget_code, r.economic_ringfence_code, r.type_code;
GO
