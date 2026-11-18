-- dw.v_statement_pnl: the group income and expenditure statement computed in SQL, one row per statement line and
-- financial year, from dw.fact_outturn and dw.fact_plan. It is the expectation for the model's Statement Amount,
-- Statement Plan and Statement Amount (plan basis); the semantic model never reads it (it reads dw.v_model_*).
--   outturn_as_reported    the sum of the line's detail lines, spending positive and income negative (GBP thousands)
--   outturn                the same, in the sign the line is presented in (income positive on an income line)
--   plan_amount            the published plan, only on a line with a plan scope, and only where the source gives a
--                          plan at that level: RESOURCE and CAPITAL where every plan row of the year is OSCAR Plans
--                          (grain A, published by economic budget), ALL in every year with a plan. Only the voted
--                          budgets are compared (RDEL, RDEL_EX_DEPN, CDEL, RAME, CAME). Administration rows (part of
--                          resource DEL) are left out. Non-departmental AME, non-budget and unclassified plan rows of
--                          OSCAR Plans are left out: the non-budget plan is gross and the outturn is net (2019-20,
--                          resource: plan 791,549,206 against outturn -9,323,463, GBP thousands).
--   outturn_plan_basis     where there is a plan, the outturn on the plan's basis: for each plan measure the year has
--                          (RDEL, RDEL_EX_DEPN, CDEL, RAME, CAME), the outturn
--                          of the control budget detail and economic budget the measure is made of, and for the
--                          excluding-depreciation measures without the PESA group DEPRECIATION, added up, within the
--                          line's economic budget.
-- A spacer has no row. A row exists where the line has outturn or a plan in that year.
-- This is a separate implementation from the model's DAX (Basis.OutturnFor): it reads the dimensions' attributes and
-- dw.plan_measure_selection.

DROP VIEW IF EXISTS dw.v_statement_pnl;
GO
CREATE VIEW dw.v_statement_pnl
AS
WITH years AS (
    SELECT financial_year FROM dw.dim_period GROUP BY financial_year
    UNION
    SELECT financial_year FROM dw.fact_plan GROUP BY financial_year
), out_line AS (
    SELECT p.financial_year, m.line_key, SUM(f.amount_delta) AS raw_amount
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS p ON p.period_key = f.period_key
    JOIN dw.account_statement_line AS a ON a.account_key = f.account_key
    JOIN dw.statement_line_member AS m ON m.detail_line_key = a.line_key
    GROUP BY p.financial_year, m.line_key
), budget_measure AS (
    SELECT measure FROM (VALUES ('RDEL'), ('RDEL_EX_DEPN'), ('CDEL'), ('RAME'), ('CAME')) AS m(measure)
), plan_year AS (
    SELECT financial_year, MAX(CASE WHEN grain_code <> 'A' THEN 1 ELSE 0 END) AS has_other_grain
    FROM dw.fact_plan
    WHERE measure IN (SELECT measure FROM budget_measure)
    GROUP BY financial_year
), scope AS (
    SELECT scope FROM (VALUES ('RESOURCE'), ('CAPITAL'), ('ALL')) AS s(scope)
), plan_scope AS (
    SELECT y.financial_year, s.scope, SUM(p.amount) AS plan_amount
    FROM plan_year AS y
    CROSS JOIN scope AS s
    JOIN dw.fact_plan AS p
      ON p.financial_year = y.financial_year AND p.measure IN (SELECT measure FROM budget_measure)
     AND (s.scope = 'ALL' OR p.economic_budget = s.scope)
    WHERE s.scope = 'ALL' OR y.has_other_grain = 0
    GROUP BY y.financial_year, s.scope
), base AS (
    SELECT p.financial_year, cb.control_budget_detail_code AS cb, a.economic_budget AS eb,
           CASE WHEN a.pesa_economic_group_code = 'DEPRECIATION' THEN 1 ELSE 0 END AS is_depreciation,
           SUM(f.amount_delta) AS amt
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS p ON p.period_key = f.period_key
    JOIN dw.dim_account AS a ON a.account_key = f.account_key
    JOIN dw.dim_control_budget AS cb ON cb.control_budget_key = f.control_budget_key
    GROUP BY p.financial_year, cb.control_budget_detail_code, a.economic_budget,
             CASE WHEN a.pesa_economic_group_code = 'DEPRECIATION' THEN 1 ELSE 0 END
), basis_rule AS (
    SELECT measure, control_budget_detail AS cb, economic_budget AS eb, 'eq' AS eb_mode, excludes_depreciation AS xd
    FROM dw.plan_measure_selection
    UNION ALL SELECT 'NON_DEPT_AME', 'NON-DEPT AME', '', 'any', 0
    UNION ALL SELECT 'NON_BUDGET', 'NON-BUDGET', '', 'any', 0
    UNION ALL SELECT 'UNCLASSIFIED', c.cb, '', 'other', 0
    FROM (VALUES ('DEL PROG'), ('DEL ADMIN'), ('DEPT AME')) AS c(cb)
), measure_year AS (
    SELECT financial_year, measure FROM dw.fact_plan WHERE measure IN (SELECT measure FROM budget_measure)
    GROUP BY financial_year, measure
), basis AS (
    SELECT my.financial_year, s.scope, SUM(b.amt) AS basis_amount
    FROM measure_year AS my
    JOIN basis_rule AS r ON r.measure = my.measure
    JOIN base AS b
      ON b.financial_year = my.financial_year AND b.cb = r.cb
     AND (r.eb_mode = 'any'
          OR (r.eb_mode = 'eq' AND b.eb = r.eb)
          OR (r.eb_mode = 'other' AND b.eb NOT IN ('RESOURCE', 'CAPITAL')))
     AND (r.xd = 0 OR b.is_depreciation = 0)
    JOIN scope AS s ON s.scope = 'ALL' OR b.eb = s.scope
    GROUP BY my.financial_year, s.scope
)
SELECT l.line_id, l.line_key, y.financial_year,
       CAST(o.raw_amount AS decimal(19, 4)) AS outturn_as_reported,
       CAST(o.raw_amount * l.sign_factor AS decimal(19, 4)) AS outturn,
       CAST(p.plan_amount * l.sign_factor AS decimal(19, 4)) AS plan_amount,
       CAST(CASE WHEN p.plan_amount IS NOT NULL THEN b.basis_amount * l.sign_factor END AS decimal(19, 4)) AS outturn_plan_basis
FROM dw.statement_line AS l
CROSS JOIN years AS y
LEFT JOIN out_line AS o ON o.line_key = l.line_key AND o.financial_year = y.financial_year
LEFT JOIN plan_scope AS p ON p.financial_year = y.financial_year AND p.scope = l.plan_scope AND l.plan_scope <> ''
LEFT JOIN basis AS b ON b.financial_year = y.financial_year AND b.scope = l.plan_scope AND l.plan_scope <> ''
WHERE l.line_type <> 'spacer'
  AND (o.raw_amount IS NOT NULL OR p.plan_amount IS NOT NULL);
GO
