-- test: every model view returns the rows of its base table, except the three documented subsets (department: the live members; fiscal year: one row per year of the calendar and of the plan; data quality: plus the "No issue flagged" member)
SELECT v.view_name, v.view_rows, v.expected_rows
FROM (VALUES
    ('dw.v_model_fiscal_period',      (SELECT COUNT_BIG(*) FROM dw.v_model_fiscal_period),      (SELECT COUNT_BIG(*) FROM dw.dim_period)),
    ('dw.v_model_fiscal_year',        (SELECT COUNT_BIG(*) FROM dw.v_model_fiscal_year),        (SELECT COUNT_BIG(DISTINCT financial_year) FROM (SELECT financial_year FROM dw.dim_period UNION SELECT financial_year FROM dw.fact_plan) AS y)),
    ('dw.v_model_release',            (SELECT COUNT_BIG(*) FROM dw.v_model_release),            (SELECT COUNT_BIG(*) FROM dw.dim_release)),
    ('dw.v_model_scenario',           (SELECT COUNT_BIG(*) FROM dw.v_model_scenario),           (SELECT COUNT_BIG(*) FROM dw.dim_scenario)),
    ('dw.v_model_account',            (SELECT COUNT_BIG(*) FROM dw.v_model_account),            (SELECT COUNT_BIG(*) FROM dw.dim_account)),
    ('dw.v_model_control_budget',     (SELECT COUNT_BIG(*) FROM dw.v_model_control_budget),     (SELECT COUNT_BIG(*) FROM dw.dim_control_budget)),
    ('dw.v_model_segment',            (SELECT COUNT_BIG(*) FROM dw.v_model_segment),            (SELECT COUNT_BIG(*) FROM dw.dim_segment)),
    ('dw.v_model_organisation',       (SELECT COUNT_BIG(*) FROM dw.v_model_organisation),       (SELECT COUNT_BIG(*) FROM dw.dim_organisation)),
    ('dw.v_model_department',         (SELECT COUNT_BIG(*) FROM dw.v_model_department),         (SELECT COUNT_BIG(*) FROM dw.current_structure_department WHERE is_live = 1)),
    ('dw.v_model_sr_group',           (SELECT COUNT_BIG(*) FROM dw.v_model_sr_group),           (SELECT COUNT_BIG(*) FROM dw.dim_sr_group)),
    ('dw.v_model_plan_source',        (SELECT COUNT_BIG(*) FROM dw.v_model_plan_source),        (SELECT COUNT_BIG(*) FROM dw.dim_plan_source)),
    ('dw.v_model_plan_grain',         (SELECT COUNT_BIG(*) FROM dw.v_model_plan_grain),         (SELECT COUNT_BIG(*) FROM dw.dim_plan_grain)),
    ('dw.v_model_data_quality',       (SELECT COUNT_BIG(*) FROM dw.v_model_data_quality),       (SELECT COUNT_BIG(*) + 1 FROM dw.dq_issue)),
    ('dw.v_model_fact_outturn',       (SELECT COUNT_BIG(*) FROM dw.v_model_fact_outturn),       (SELECT COUNT_BIG(*) FROM dw.fact_outturn)),
    ('dw.v_model_fact_plan',          (SELECT COUNT_BIG(*) FROM dw.v_model_fact_plan),          (SELECT COUNT_BIG(*) FROM dw.fact_plan)),
    ('dw.v_model_fact_plan_phased',   (SELECT COUNT_BIG(*) FROM dw.v_model_fact_plan_phased),   (SELECT COUNT_BIG(*) FROM dw.fact_plan_phased)),
    ('dw.v_model_statement_line',     (SELECT COUNT_BIG(*) FROM dw.v_model_statement_line),     (SELECT COUNT_BIG(*) FROM dw.statement_line))
) AS v(view_name, view_rows, expected_rows)
WHERE v.view_rows <> v.expected_rows;
