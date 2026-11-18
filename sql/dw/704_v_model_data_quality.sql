-- The model's view layer, part 5: the data-quality findings.
--   dw.v_model_data_quality  dw.dq_issue plus one member, dq_issue_key 0 "No issue flagged", so that every
--                            outturn row has a key that exists (a nullable key would add a blank member to the
--                            relationship). The member is a label, not data: it holds no amount and no row of
--                            dw.dq_issue is changed. dq_issue_id is never 0 (the build numbers findings from 1).

DROP VIEW IF EXISTS dw.v_model_data_quality;
GO
CREATE VIEW dw.v_model_data_quality
AS
SELECT dq_issue_id AS dq_issue_key, issue_rule, issue_type, flags_fact_rows, description, treatment,
       release_from, release_to, organisation_code, sub_segment_code, economic_category_code,
       control_budget_detail_code, period_key, amount_before, amount_after, rows_affected
FROM dw.dq_issue
UNION ALL
SELECT 0, CAST('-' AS char(1)), CAST('No issue flagged' AS varchar(40)), CAST(0 AS bit),
       CAST(N'No data-quality finding applies to this row.' AS nvarchar(2000)),
       CAST(N'None.' AS nvarchar(1000)), CAST(NULL AS varchar(7)), CAST(NULL AS varchar(7)),
       CAST(NULL AS nvarchar(100)), CAST(NULL AS nvarchar(100)), CAST(NULL AS nvarchar(100)),
       CAST(NULL AS nvarchar(200)), CAST(NULL AS int), CAST(NULL AS decimal(19, 4)), CAST(NULL AS decimal(19, 4)),
       CAST(0 AS int);
GO
