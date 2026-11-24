-- scope: full
-- audit.tac_sofp_balance: for every provider, year and column, whether the balance sheet balances: total assets
-- employed (BAL1400) against total taxpayers' and others' equity (BAL1500). Every pair is listed, the ones that
-- balance and the ones that do not; nothing is filtered out.
--   balance_class   exact       the two are equal
--                   rounding    they differ by less than 1 (GBP 1,000): the providers fill the form in thousands
--                               and some carry the pounds below, so their lines do not add to the thousand
--                   exception   they differ by 1 or more (GBP 1,000 or more)
-- A pair where one of the two values is missing cannot occur in the real files (a test says so).

DROP TABLE IF EXISTS audit.tac_sofp_balance;
GO

SELECT p.provider_key, p.provider_code, a.release, a.period_column,
       a.value AS total_assets_employed, e.value AS total_equity,
       a.value - e.value AS difference,
       CAST(CASE WHEN a.value = e.value THEN 'exact' WHEN ABS(a.value - e.value) < 1 THEN 'rounding' ELSE 'exception' END
            AS varchar(10)) AS balance_class
INTO audit.tac_sofp_balance
FROM dw.tac_fact AS a
JOIN dw.tac_statutory_line AS la ON la.line_key = a.line_key AND la.sub_code = 'BAL1400'
JOIN dw.tac_fact AS e ON e.provider_key = a.provider_key AND e.release = a.release AND e.period_column = a.period_column
JOIN dw.tac_statutory_line AS le ON le.line_key = e.line_key AND le.sub_code = 'BAL1500'
JOIN dw.tac_provider AS p ON p.provider_key = a.provider_key;
GO

ALTER TABLE audit.tac_sofp_balance ALTER COLUMN release varchar(7) NOT NULL;
GO
ALTER TABLE audit.tac_sofp_balance ALTER COLUMN period_column char(2) NOT NULL;
GO
ALTER TABLE audit.tac_sofp_balance ADD CONSTRAINT pk_audit_tac_sofp_balance
    PRIMARY KEY (provider_key, release, period_column);
GO
