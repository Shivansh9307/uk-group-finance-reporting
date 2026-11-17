-- scope: full
-- stg.bud_account_hierarchy: economic category -> economic group -> economic budget, read from all 15 BUD
-- workbooks. The hierarchy does not change between vintages, so it is one row per combination as it
-- appears, with the vintages and years it occurs in, not one row per vintage.
--   n_chart_of_accounts_l5_codes = distinct chart-of-accounts level 5 codes under the category.
--   is_latest_vintage = the combination occurs in the newest annual release loaded.
-- Reads every row of raw.oscar_bud, Closed ones included (they repeat rows held under another status).

DROP TABLE IF EXISTS stg.bud_account_hierarchy;
GO

CREATE TABLE stg.bud_account_hierarchy (
    economic_category_code       nvarchar(20)  NOT NULL,
    economic_category_name       nvarchar(200) NOT NULL,
    economic_group_code          nvarchar(20)  NOT NULL,
    economic_group_name          nvarchar(200) NOT NULL,
    economic_budget_code         nvarchar(100) NOT NULL,
    n_chart_of_accounts_l5_codes int           NOT NULL,
    vintages                     varchar(40)   NOT NULL,   -- e.g. '2023-11 2024-11 2025-11'
    financial_years              varchar(100)  NOT NULL,
    source_rows                  int           NOT NULL,
    is_latest_vintage            bit           NOT NULL,
    CONSTRAINT pk_stg_bud_account_hierarchy PRIMARY KEY
        (economic_category_code, economic_category_name, economic_group_code, economic_group_name, economic_budget_code)
);
GO

WITH k AS (
    SELECT economic_category_code, economic_category_long_name AS economic_category_name,
           economic_group_code, economic_group_long_name AS economic_group_name, economic_budget_code,
           vintage, LEFT(year_no, 4) + '-' + RIGHT(year_no, 2) AS financial_year,
           chart_of_accounts_l5_code
    FROM raw.oscar_bud
), l5 AS (
    SELECT economic_category_code, economic_category_name, economic_group_code, economic_group_name,
           economic_budget_code, COUNT(DISTINCT chart_of_accounts_l5_code) AS n_l5
    FROM k
    GROUP BY economic_category_code, economic_category_name, economic_group_code, economic_group_name, economic_budget_code
), by_v AS (
    SELECT economic_category_code, economic_category_name, economic_group_code, economic_group_name,
           economic_budget_code, vintage, COUNT_BIG(*) AS source_rows
    FROM k
    GROUP BY economic_category_code, economic_category_name, economic_group_code, economic_group_name,
             economic_budget_code, vintage
), by_y AS (
    SELECT DISTINCT economic_category_code, economic_category_name, economic_group_code, economic_group_name,
           economic_budget_code, financial_year
    FROM k
), v_text AS (
    SELECT economic_category_code, economic_category_name, economic_group_code, economic_group_name,
           economic_budget_code,
           STRING_AGG(vintage, ' ') WITHIN GROUP (ORDER BY vintage) AS vintages,
           SUM(source_rows) AS source_rows
    FROM by_v
    GROUP BY economic_category_code, economic_category_name, economic_group_code, economic_group_name, economic_budget_code
), y_text AS (
    SELECT economic_category_code, economic_category_name, economic_group_code, economic_group_name,
           economic_budget_code,
           STRING_AGG(financial_year, ' ') WITHIN GROUP (ORDER BY financial_year) AS financial_years
    FROM by_y
    GROUP BY economic_category_code, economic_category_name, economic_group_code, economic_group_name, economic_budget_code
), latest AS (
    SELECT MAX(vintage) AS vintage FROM raw.oscar_bud_file WHERE load_status = 'loaded'
)
INSERT INTO stg.bud_account_hierarchy
SELECT v.economic_category_code, v.economic_category_name, v.economic_group_code, v.economic_group_name,
       v.economic_budget_code, l5.n_l5, v.vintages, y.financial_years, v.source_rows,
       CAST(CASE WHEN EXISTS (SELECT 1 FROM by_v AS b
                              WHERE b.economic_category_code = v.economic_category_code
                                AND b.economic_category_name = v.economic_category_name
                                AND b.economic_group_code = v.economic_group_code
                                AND b.economic_group_name = v.economic_group_name
                                AND b.economic_budget_code = v.economic_budget_code
                                AND b.vintage = (SELECT vintage FROM latest))
                 THEN 1 ELSE 0 END AS bit)
FROM v_text AS v
JOIN y_text AS y ON y.economic_category_code = v.economic_category_code AND y.economic_category_name = v.economic_category_name
                AND y.economic_group_code = v.economic_group_code AND y.economic_group_name = v.economic_group_name
                AND y.economic_budget_code = v.economic_budget_code
JOIN l5 ON l5.economic_category_code = v.economic_category_code AND l5.economic_category_name = v.economic_category_name
       AND l5.economic_group_code = v.economic_group_code AND l5.economic_group_name = v.economic_group_name
       AND l5.economic_budget_code = v.economic_budget_code
ORDER BY v.economic_category_code, v.economic_category_name, v.economic_group_code, v.economic_budget_code;
GO
