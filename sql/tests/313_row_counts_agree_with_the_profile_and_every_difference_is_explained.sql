-- test: the independent recount agrees with the profiled delta row count for every release, and the differences between the fact and the profile are fully explained (rounding, key changes within a year, letter case of a code)
SELECT release, profile_rows, exact_cs_rows, fact_rows, profile_diff_rows, unexplained_rows,
       fact_rows - profile_rows - case_rows - rounding_rows - key_rows AS unaccounted
FROM audit.delta_rowcount
WHERE profile_diff_rows <> 0 OR unexplained_rows <> 0
   OR fact_rows - profile_rows - case_rows - rounding_rows - key_rows <> 0
UNION ALL
SELECT 'fact total', (SELECT SUM(profile_rows) FROM audit.delta_rowcount), NULL, (SELECT COUNT(*) FROM dw.fact_outturn), NULL, NULL,
       (SELECT COUNT(*) FROM dw.fact_outturn) - (SELECT SUM(fact_rows) FROM audit.delta_rowcount)
WHERE (SELECT COUNT(*) FROM dw.fact_outturn) <> (SELECT SUM(fact_rows) FROM audit.delta_rowcount)
UNION ALL
SELECT 'releases in audit.delta_rowcount', NULL, NULL, COUNT(*), NULL, NULL, NULL
FROM audit.delta_rowcount HAVING COUNT(*) <> 31;
