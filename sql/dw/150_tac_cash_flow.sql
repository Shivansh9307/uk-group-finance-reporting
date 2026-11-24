-- scope: full
-- The indirect cash flow of every NHS provider, derived from the income statement and the balance sheet, and the
-- table that says which published cash-flow lines it is compared with.
--   dw.tac_cash_flow_line        the lines of the derived cash flow (authored/tac_cash_flow_line.csv): label, section,
--                                order and whether the line is compared with a published line (compared), exists only
--                                on the derived side (derived_only) or only on the published side (published_only)
--   dw.tac_cash_flow_derived     DERIVED. One row per provider, file year and derived line: the cash effect, in GBP
--                                thousands, on the TAC sign (an inflow is positive). A balance-sheet input is the
--                                movement of the year, the current-year column less the prior-year column of the same
--                                file, so a restatement of the opening balance does not leak in; an income-statement
--                                input is the current-year flow. The inputs, their factor (-1 for an asset or a
--                                liability, +1 for equity) and the derived line they feed are in
--                                authored/tac_cash_flow_map.csv, one row per statement line with a note. A derived line
--                                that no input feeds is 0 by construction.
--   dw.tac_cash_flow_comparison  which derived line each published cash-flow line (a line, never a subtotal) is
--                                compared with
-- The provider and statement-line keys are checked by a test (sql/tests/150 onwards), not by a foreign key, so that
-- sql/dw/100 and 105 can still drop their tables when a build runs into an existing database.
-- Real data goes in, and the result is derived, not published: it never joins a real total (a test says so), and the
-- difference to the published cash flow is reported, never forced to zero (audit.tac_cash_flow_*).

DROP TABLE IF EXISTS dw.tac_cash_flow_comparison;
GO
DROP TABLE IF EXISTS dw.tac_cash_flow_derived;
GO
DROP TABLE IF EXISTS dw.tac_cash_flow_line;
GO

CREATE TABLE dw.tac_cash_flow_line (
    cash_flow_line_key  int            NOT NULL CONSTRAINT pk_dw_tac_cash_flow_line PRIMARY KEY,
    line_code           varchar(20)    NOT NULL CONSTRAINT uq_dw_tac_cash_flow_line_code UNIQUE,
    label               nvarchar(200)  NOT NULL,
    section             nvarchar(60)   NOT NULL,
    sort_order          int            NOT NULL,
    line_kind           varchar(20)    NOT NULL,
    note                nvarchar(1000) NOT NULL
);
GO

CREATE TABLE dw.tac_cash_flow_derived (
    provider_key        int            NOT NULL,
    release             varchar(7)     NOT NULL,
    cash_flow_line_key  int            NOT NULL,
    amount              decimal(19,4)  NOT NULL,
    is_derived          bit            NOT NULL CONSTRAINT df_dw_tac_cash_flow_derived_flag DEFAULT (1),
    CONSTRAINT pk_dw_tac_cash_flow_derived PRIMARY KEY (provider_key, release, cash_flow_line_key),
    CONSTRAINT fk_dw_tac_cash_flow_derived_line FOREIGN KEY (cash_flow_line_key) REFERENCES dw.tac_cash_flow_line (cash_flow_line_key)
);
GO

CREATE TABLE dw.tac_cash_flow_comparison (
    line_key            int            NOT NULL CONSTRAINT pk_dw_tac_cash_flow_comparison PRIMARY KEY,
    cash_flow_line_key  int            NOT NULL,
    CONSTRAINT fk_dw_tac_cash_flow_comparison_derived FOREIGN KEY (cash_flow_line_key) REFERENCES dw.tac_cash_flow_line (cash_flow_line_key)
);
GO

INSERT INTO dw.tac_cash_flow_line (cash_flow_line_key, line_code, label, section, sort_order, line_kind, note)
SELECT sort_order, line_code, label, section, sort_order, line_kind, note
FROM stg.tac_cash_flow_line;
GO

INSERT INTO dw.tac_cash_flow_comparison (line_key, cash_flow_line_key)
SELECT l.line_key, d.cash_flow_line_key
FROM stg.tac_cash_flow_map AS m
JOIN dw.tac_statutory_line AS l ON l.sub_code = m.sub_code
JOIN dw.tac_cash_flow_line AS d ON d.line_code = m.derived_line
WHERE m.treatment = 'compare';
GO

-- one row per provider and year with statements, times every derived line; the input values are added by line
WITH provider_year AS (
    SELECT DISTINCT provider_key, release FROM dw.tac_fact
),
input AS (
    SELECT l.line_key, m.basis, m.factor, d.cash_flow_line_key
    FROM stg.tac_cash_flow_map AS m
    JOIN dw.tac_statutory_line AS l ON l.sub_code = m.sub_code
    JOIN dw.tac_cash_flow_line AS d ON d.line_code = m.derived_line
    WHERE m.treatment = 'derive'
),
effect AS (
    -- a line the form does not carry in a year (a retired line, a line added later) is 0, not missing
    SELECT py.provider_key, py.release, i.cash_flow_line_key,
           i.factor * CASE i.basis
                          WHEN 'movement' THEN ISNULL(cy.value, 0) - ISNULL(pv.value, 0)
                          ELSE ISNULL(cy.value, 0)
                      END AS cash_effect
    FROM provider_year AS py
    CROSS JOIN input AS i
    LEFT JOIN dw.tac_fact AS cy ON cy.provider_key = py.provider_key AND cy.release = py.release
                               AND cy.line_key = i.line_key AND cy.period_column = 'CY'
    LEFT JOIN dw.tac_fact AS pv ON pv.provider_key = py.provider_key AND pv.release = py.release
                               AND pv.line_key = i.line_key AND pv.period_column = 'PY'
)
INSERT INTO dw.tac_cash_flow_derived (provider_key, release, cash_flow_line_key, amount)
SELECT py.provider_key, py.release, d.cash_flow_line_key, CAST(ISNULL(SUM(e.cash_effect), 0) AS decimal(19,4))
FROM provider_year AS py
CROSS JOIN dw.tac_cash_flow_line AS d
LEFT JOIN effect AS e ON e.provider_key = py.provider_key AND e.release = py.release
                     AND e.cash_flow_line_key = d.cash_flow_line_key
GROUP BY py.provider_key, py.release, d.cash_flow_line_key;
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'The lines of the derived indirect cash flow and their sections. AUTHORED (authored/tac_cash_flow_line.csv): labels and sections, no amount.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'tac_cash_flow_line';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'DERIVED indirect cash flow of each NHS provider and year, GBP thousand, TAC sign: balance-sheet movements (current year less prior year of the same file) and income-statement flows added by the authored map authored/tac_cash_flow_map.csv. Real inputs, derived result: never part of a real total, and compared with, not forced to, the published cash flow.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'tac_cash_flow_derived';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'Which derived cash-flow line each published cash-flow line is compared with. AUTHORED (authored/tac_cash_flow_map.csv), no amount.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'tac_cash_flow_comparison';
GO
