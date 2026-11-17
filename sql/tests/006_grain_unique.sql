-- test: stg.inyear_snapshot is unique on (release, organisation, sub-segment, economic category, control budget detail, period)
-- The primary key enforces this at load time; the test states it and reads it back from the data.

SELECT release, organisation_code, sub_segment_code, economic_category_code, control_budget_detail_code,
       period, COUNT_BIG(*) AS n
FROM stg.inyear_snapshot
GROUP BY release, organisation_code, sub_segment_code, economic_category_code, control_budget_detail_code, period
HAVING COUNT_BIG(*) > 1;
