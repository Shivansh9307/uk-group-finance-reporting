-- test: the derived cash flow has one row per provider-year with statements and derived line; every amount equals the inputs of the authored map recomputed from the sub codes of dw.tac_fact (a movement is the current-year column less the prior-year column of the same file, a flow is the current-year column, a line the form does not carry is 0); three lines are also pinned to the statements by hand (operating surplus equals the published cash flow's, inventories and public dividend capital are the balance sheet movements); every row is flagged derived
-- marker: localdata
-- requires: dw.tac_cash_flow_derived, stg.tac_cash_flow_map
WITH py AS (
    SELECT DISTINCT provider_key, release FROM dw.tac_fact
),
val AS (
    SELECT f.provider_key, f.release, l.sub_code, f.period_column, f.value
    FROM dw.tac_fact AS f JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key
),
rec AS (
    SELECT py.provider_key, py.release, d.line_code,
           SUM(m.factor * CASE m.basis
                              WHEN 'movement' THEN ISNULL(cy.value, 0) - ISNULL(pv.value, 0)
                              ELSE ISNULL(cy.value, 0) END) AS amount
    FROM py
    CROSS JOIN stg.tac_cash_flow_map AS m
    JOIN stg.tac_cash_flow_line AS d ON d.line_code = m.derived_line
    LEFT JOIN val AS cy ON cy.provider_key = py.provider_key AND cy.release = py.release AND cy.sub_code = m.sub_code AND cy.period_column = 'CY'
    LEFT JOIN val AS pv ON pv.provider_key = py.provider_key AND pv.release = py.release AND pv.sub_code = m.sub_code AND pv.period_column = 'PY'
    WHERE m.treatment = 'derive'
    GROUP BY py.provider_key, py.release, d.line_code
),
want AS (
    SELECT py.provider_key, py.release, d.line_code, ISNULL(r.amount, 0) AS amount
    FROM py CROSS JOIN stg.tac_cash_flow_line AS d
    LEFT JOIN rec AS r ON r.provider_key = py.provider_key AND r.release = py.release AND r.line_code = d.line_code
),
have AS (
    SELECT x.provider_key, x.release, d.line_code, x.amount, x.is_derived
    FROM dw.tac_cash_flow_derived AS x JOIN dw.tac_cash_flow_line AS d ON d.cash_flow_line_key = x.cash_flow_line_key
)
SELECT w.provider_key, w.release, w.line_code, 'derived amount differs from the recomputation or is missing' AS problem
FROM want AS w LEFT JOIN have AS h ON h.provider_key = w.provider_key AND h.release = w.release AND h.line_code = w.line_code
WHERE h.line_code IS NULL OR ABS(h.amount - w.amount) >= 0.0001
UNION ALL
SELECT h.provider_key, h.release, h.line_code, 'derived row for a provider-year without statements, or a row not flagged derived'
FROM have AS h LEFT JOIN py ON py.provider_key = h.provider_key AND py.release = h.release
WHERE py.provider_key IS NULL OR h.is_derived <> 1
UNION ALL
-- by hand: the operating surplus the cash flow starts from is the published SCF0100A
SELECT x.provider_key, x.release, 'D_OP_SURPLUS', 'operating surplus differs from the published cash flow start line'
FROM dw.tac_cash_flow_derived AS x
JOIN dw.tac_cash_flow_line AS d ON d.cash_flow_line_key = x.cash_flow_line_key AND d.line_code = 'D_OP_SURPLUS'
JOIN dw.tac_fact AS f ON f.provider_key = x.provider_key AND f.release = x.release AND f.period_column = 'CY'
JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key AND l.sub_code = 'SCF0100A'
WHERE ABS(x.amount - f.value) >= 0.01
UNION ALL
-- by hand: inventories are minus the movement of BAL1190, public dividend capital the movement of BAL1410
SELECT x.provider_key, x.release, d.line_code, 'balance sheet movement line differs from the statements'
FROM dw.tac_cash_flow_derived AS x
JOIN dw.tac_cash_flow_line AS d ON d.cash_flow_line_key = x.cash_flow_line_key AND d.line_code IN ('D_OP_INV', 'D_FI_PDC')
JOIN dw.tac_statutory_line AS l ON l.sub_code = CASE d.line_code WHEN 'D_OP_INV' THEN 'BAL1190' ELSE 'BAL1410' END
LEFT JOIN dw.tac_fact AS cy ON cy.provider_key = x.provider_key AND cy.release = x.release AND cy.line_key = l.line_key AND cy.period_column = 'CY'
LEFT JOIN dw.tac_fact AS pv ON pv.provider_key = x.provider_key AND pv.release = x.release AND pv.line_key = l.line_key AND pv.period_column = 'PY'
WHERE ABS(x.amount - CASE d.line_code WHEN 'D_OP_INV' THEN -1 ELSE 1 END * (ISNULL(cy.value, 0) - ISNULL(pv.value, 0))) >= 0.0001;
