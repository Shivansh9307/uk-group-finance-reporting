-- Independent of the model: the primary-file rows of the file control and the rows of the plan coverage.
SELECT (SELECT COUNT_BIG(*) FROM audit.file_control WHERE primary_for_release = 'Y') AS file_control_rows,
       (SELECT COUNT_BIG(*) FROM dw.plan_coverage) AS plan_coverage_rows;
