-- scope: full
-- The derived (indirect) cash flow against the published cash flow, by derived line and by section, one row per file
-- year. Residual = derived less published, GBP thousand, TAC sign. Nothing is forced to zero.
--   audit.tac_cash_flow_line_residual     one row per file year and derived line: the derived amount added over the
--                                         providers, the published lines the derived line is compared with added over
--                                         the providers (current-year column), and the difference
--   audit.tac_cash_flow_section_residual  the same by section, plus a row 'Net change in cash' that adds every derived
--                                         line against the published increase in cash (SCF0320)
-- A derived line with kind derived_only has no published line (published 0); one with kind published_only has no
-- derived amount (derived 0). The residual of a line is what the two statements cannot be made to agree on from the
-- income statement and balance sheet alone: non-cash items, transfers by absorption, mergers, restated openings.

DROP TABLE IF EXISTS audit.tac_cash_flow_section_residual;
GO
DROP TABLE IF EXISTS audit.tac_cash_flow_line_residual;
GO

SELECT CAST(r.release AS varchar(7)) AS release, d.cash_flow_line_key, d.line_code, d.label, d.section, d.sort_order, d.line_kind,
       r.derived_total, r.published_total,
       CAST(r.derived_total - r.published_total AS decimal(19,4)) AS residual,
       r.providers
INTO audit.tac_cash_flow_line_residual
FROM dw.tac_cash_flow_line AS d
JOIN (SELECT y.release, y.cash_flow_line_key,
             CAST(SUM(y.amount) AS decimal(19,4)) AS derived_total,
             CAST(ISNULL(MAX(p.published_total), 0) AS decimal(19,4)) AS published_total,
             COUNT_BIG(*) AS providers
      FROM dw.tac_cash_flow_derived AS y
      LEFT JOIN (SELECT f.release, c.cash_flow_line_key, SUM(f.value) AS published_total
                 FROM dw.tac_fact AS f
                 JOIN dw.tac_cash_flow_comparison AS c ON c.line_key = f.line_key
                 WHERE f.period_column = 'CY'
                 GROUP BY f.release, c.cash_flow_line_key) AS p
             ON p.release = y.release AND p.cash_flow_line_key = y.cash_flow_line_key
      GROUP BY y.release, y.cash_flow_line_key) AS r ON r.cash_flow_line_key = d.cash_flow_line_key;
GO
ALTER TABLE audit.tac_cash_flow_line_residual ALTER COLUMN release varchar(7) NOT NULL;
GO
ALTER TABLE audit.tac_cash_flow_line_residual ADD CONSTRAINT pk_audit_tac_cash_flow_line_residual PRIMARY KEY (release, cash_flow_line_key);
GO

SELECT CAST(release AS varchar(7)) AS release, CAST(section AS nvarchar(60)) AS section, CAST(MIN(sort_order) AS int) AS first_sort_order,
       CAST(SUM(derived_total) AS decimal(19,4)) AS derived_total,
       CAST(SUM(published_total) AS decimal(19,4)) AS published_total,
       CAST(SUM(residual) AS decimal(19,4)) AS residual
INTO audit.tac_cash_flow_section_residual
FROM audit.tac_cash_flow_line_residual
GROUP BY release, section;
GO
INSERT INTO audit.tac_cash_flow_section_residual (release, section, first_sort_order, derived_total, published_total, residual)
SELECT r.release, N'Net change in cash', 99, r.derived_total, ISNULL(p.published_total, 0), r.derived_total - ISNULL(p.published_total, 0)
FROM (SELECT release, SUM(derived_total) AS derived_total FROM audit.tac_cash_flow_line_residual GROUP BY release) AS r
LEFT JOIN (SELECT f.release, SUM(f.value) AS published_total
           FROM dw.tac_fact AS f JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key AND l.sub_code = 'SCF0320'
           WHERE f.period_column = 'CY' GROUP BY f.release) AS p ON p.release = r.release;
GO
ALTER TABLE audit.tac_cash_flow_section_residual ALTER COLUMN release varchar(7) NOT NULL;
GO
ALTER TABLE audit.tac_cash_flow_section_residual ALTER COLUMN section nvarchar(60) NOT NULL;
GO
ALTER TABLE audit.tac_cash_flow_section_residual ADD CONSTRAINT pk_audit_tac_cash_flow_section_residual PRIMARY KEY (release, section);
GO
