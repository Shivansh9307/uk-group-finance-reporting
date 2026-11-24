-- scope: full
-- The audit tables of the pay bridge (the views are in sql/audit/900). All amounts are pounds, not GBP thousands.
--   audit.pay_excluded_cell     every organisation-month cell that is not valid (dw.v_pay_cell) and the reason; none of
--                               them is in the bridge
--   audit.pay_bridge_not_bridged every department, organisation and month row of the bridge that is left out, and why
--   audit.pay_bridge_tie        the bridge of every department and month it can be built for: prior paybill, volume, rate,
--                               mix, entry and exit, current paybill, and the difference, which is zero
--     volume = (change in full-time equivalent of the continuing organisations) x (their prior average cost)
--     rate   = sum over continuing organisations of the current full-time equivalent x the change in average cost
--     mix    = the sum of the organisations' own volume less the department's volume
--     entry_exit = the paybill of organisations valid now and not a year ago, less that of organisations valid a year ago and not now
--     difference = (current - prior) - (volume + rate + mix + entry_exit)

DROP TABLE IF EXISTS audit.pay_bridge_tie;
GO
DROP TABLE IF EXISTS audit.pay_bridge_not_bridged;
GO
DROP TABLE IF EXISTS audit.pay_excluded_cell;
GO

SELECT durable_key, month_start, report_month, department_key, fte, paybill, cell_status AS reason
INTO audit.pay_excluded_cell
FROM dw.v_pay_cell
WHERE cell_status <> 'valid';
GO
ALTER TABLE audit.pay_excluded_cell ADD CONSTRAINT pk_audit_pay_excluded_cell PRIMARY KEY (durable_key, month_start);
GO

SELECT department_key, durable_key, month_start, not_bridged_reason AS reason, fte_cur, pay_cur, fte_prior, pay_prior
INTO audit.pay_bridge_not_bridged
FROM dw.v_pay_bridge_row
WHERE bridge_class = 'not_bridged';
GO

WITH d AS (
    SELECT department_key, month_start,
           SUM(CASE WHEN bridge_class IN ('continuing', 'exit') THEN pay_prior END) AS prior_paybill,
           SUM(CASE WHEN bridge_class IN ('continuing', 'entry') THEN pay_cur END) AS current_paybill,
           SUM(CASE WHEN bridge_class = 'continuing' THEN fte_cur END) AS fte_cur_c,
           SUM(CASE WHEN bridge_class = 'continuing' THEN fte_prior END) AS fte_prior_c,
           SUM(CASE WHEN bridge_class = 'continuing' THEN pay_prior END) AS pay_prior_c,
           SUM(volume_org) AS volume_org_sum,
           SUM(rate_org) AS rate,
           SUM(CASE WHEN bridge_class = 'entry' THEN pay_cur END) AS entry_paybill,
           SUM(CASE WHEN bridge_class = 'exit' THEN pay_prior END) AS exit_paybill,
           SUM(CASE WHEN bridge_class = 'continuing' THEN 1 ELSE 0 END) AS n_continuing,
           SUM(CASE WHEN bridge_class = 'entry' THEN 1 ELSE 0 END) AS n_entry,
           SUM(CASE WHEN bridge_class = 'exit' THEN 1 ELSE 0 END) AS n_exit
    FROM dw.v_model_pay_bridge
    WHERE bridge_class <> 'not_bridged'
    GROUP BY department_key, month_start
),
v AS (
    SELECT d.*,
           CAST(CASE WHEN fte_prior_c > 0
                     THEN CAST(fte_cur_c - fte_prior_c AS decimal(24, 10)) * CAST(pay_prior_c AS decimal(24, 10))
                          / CAST(fte_prior_c AS decimal(24, 10)) END AS decimal(19, 4)) AS volume
    FROM d
)
SELECT department_key, month_start,
       CAST(ISNULL(prior_paybill, 0) AS decimal(19, 4)) AS prior_paybill,
       CAST(ISNULL(volume, 0) AS decimal(19, 4)) AS volume,
       CAST(ISNULL(rate, 0) AS decimal(19, 4)) AS rate,
       CAST(ISNULL(volume_org_sum, 0) - ISNULL(volume, 0) AS decimal(19, 4)) AS mix,
       CAST(ISNULL(entry_paybill, 0) - ISNULL(exit_paybill, 0) AS decimal(19, 4)) AS entry_exit,
       CAST(ISNULL(current_paybill, 0) AS decimal(19, 4)) AS current_paybill,
       CAST(ISNULL(current_paybill, 0) - ISNULL(prior_paybill, 0)
            - (ISNULL(volume, 0) + ISNULL(rate, 0) + (ISNULL(volume_org_sum, 0) - ISNULL(volume, 0))
               + ISNULL(entry_paybill, 0) - ISNULL(exit_paybill, 0)) AS decimal(19, 4)) AS difference,
       CAST(n_continuing AS int) AS n_continuing, CAST(n_entry AS int) AS n_entry, CAST(n_exit AS int) AS n_exit
INTO audit.pay_bridge_tie
FROM v;
GO
ALTER TABLE audit.pay_bridge_tie ALTER COLUMN department_key int NOT NULL;
GO
ALTER TABLE audit.pay_bridge_tie ALTER COLUMN month_start date NOT NULL;
GO
ALTER TABLE audit.pay_bridge_tie ADD CONSTRAINT pk_audit_pay_bridge_tie PRIMARY KEY (department_key, month_start);
GO
