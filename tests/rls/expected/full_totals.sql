-- Independent of the model: the three headline totals of the facts with no user and no filter, which no role may see.
SELECT CAST((SELECT SUM(amount_delta) FROM dw.fact_outturn) AS decimal(38, 4)) AS outturn,
       CAST((SELECT SUM(amount) FROM dw.fact_plan WHERE is_part_of_other_measure = 0) AS decimal(38, 4)) AS [plan],
       CAST((SELECT SUM(amount) FROM dw.fact_plan_phased WHERE is_part_of_other_measure = 0) AS decimal(38, 4)) AS plan_phased;
