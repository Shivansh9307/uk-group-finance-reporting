-- scope: full
-- The allocation of a real shared-cost pool across departments by payroll full-time equivalent (the rule is
-- authored.allocation_rule; the pool, the weights and the paybill are real, the allocation is mine).
-- DERIVED. The files sit in sql/audit/ because they read dw.v_pay_cell (sql/audit/900), the valid organisation-month cells of the
-- pay bridge, so that the allocation and the pay bridge agree on who is in a department. Nothing authored is an amount and nothing
-- synthetic is read.
--
--   dw.allocation_pool           one row per rule and financial year: the pool, the sum of the revision deltas of the real outturn
--                                (dw.fact_outturn) of the pool department in the pool control budget detail, GBP thousands
--   audit.allocation_participation  one row per rule, financial year and department with at least one valid payroll cell in the
--                                year: the months present, the average monthly full-time equivalent, whether the department takes
--                                part (months present at least authored.allocation_rule.min_months), and for a department left out the
--                                weight it would have had; the departments that publish no workforce file are not rows (see the summary)
--   dw.fact_allocation           one row per rule, financial year and participating department: pool, weight, allocated amount, the
--                                rounding adjustment (non-zero on one row per rule and year) and the annualised paybill, GBP thousands
--   audit.allocation_year_summary   one row per rule and year: the tie of the allocated amounts to the pool and who is left out
--
-- Year of a month: the financial year that starts in April (April 2024 to March 2025 is 2024-25).
-- Full-time equivalent of a department in a year: the average, over the months in which the department has at least one valid
-- payroll cell, of the sum of its valid cells in the month, rounded to four decimals. A valid cell is a cell with a positive
-- full-time equivalent and paybill and no row-arithmetic fault (dw.v_pay_cell).
-- Weight: the full-time equivalent of the department over the sum of the participants. Allocated amount: the pool times the weight,
-- worked in integers of one ten-thousandth of a thousand pounds (the scale of the stored amounts) so that nothing is lost to a
-- decimal scale, rounded half away from zero; the remainder to the pool is added to the participant with the largest full-time
-- equivalent (the lower department number on a tie), so that the allocated amounts add up to the pool exactly.
-- Annualised paybill: the average monthly paybill of the valid cells over the months present times 12, in GBP thousands (the cells are in pounds).

DROP TABLE IF EXISTS audit.allocation_year_summary;
GO
DROP TABLE IF EXISTS dw.fact_allocation;
GO
DROP TABLE IF EXISTS audit.allocation_participation;
GO
DROP TABLE IF EXISTS dw.allocation_pool;
GO

CREATE TABLE dw.allocation_pool (
    pool_key             int            NOT NULL CONSTRAINT pk_dw_allocation_pool PRIMARY KEY,
    rule_id              varchar(30)    NOT NULL,
    financial_year       varchar(7)     NOT NULL,
    pool_department_key  int            NOT NULL,
    pool_amount          decimal(19,4)  NOT NULL,
    pool_rows            bigint         NOT NULL,
    CONSTRAINT uq_dw_allocation_pool UNIQUE (rule_id, financial_year)
);
GO

INSERT INTO dw.allocation_pool (pool_key, rule_id, financial_year, pool_department_key, pool_amount, pool_rows)
SELECT ROW_NUMBER() OVER (ORDER BY g.rule_id, g.financial_year), g.rule_id, g.financial_year, g.department_key, g.pool_amount, g.pool_rows
FROM (
    SELECT r.rule_id, p.financial_year, d.department_key, SUM(f.amount_delta) AS pool_amount, COUNT_BIG(*) AS pool_rows
    FROM authored.allocation_rule AS r
    JOIN dw.dim_department AS d ON d.department_number = r.pool_department_number AND d.is_current = 1
    JOIN dw.dim_control_budget AS cb ON cb.control_budget_detail_code = r.pool_control_budget_detail_code
    JOIN dw.fact_outturn AS f ON f.current_department_key = d.department_key AND f.control_budget_key = cb.control_budget_key
    JOIN dw.dim_period AS p ON p.period_key = f.period_key
    WHERE p.financial_year BETWEEN r.first_financial_year AND r.last_financial_year
    GROUP BY r.rule_id, p.financial_year, d.department_key
) AS g;
GO

CREATE TABLE audit.allocation_participation (
    rule_id              varchar(30)    NOT NULL,
    financial_year       varchar(7)     NOT NULL,
    department_key       int            NOT NULL,
    months_present       int            NOT NULL,
    fte_sum              decimal(19,4)  NOT NULL,   -- sum over the months present of the department's monthly full-time equivalent
    avg_fte              decimal(19,4)  NOT NULL,   -- fte_sum over months_present, rounded to four decimals
    paybill_sum_gbp      decimal(19,4)  NOT NULL,   -- pounds, summed over the months present
    orgs_min             int            NOT NULL,   -- the fewest valid organisation cells in a month present
    orgs_max             int            NOT NULL,
    status               varchar(20)    NOT NULL,   -- participant | too_few_months
    would_be_weight      decimal(19,10) NULL,       -- for too_few_months: the weight it would have had if it took part
    CONSTRAINT pk_audit_allocation_participation PRIMARY KEY (rule_id, financial_year, department_key),
    CONSTRAINT ck_audit_allocation_participation_status CHECK (status IN ('participant', 'too_few_months'))
);
GO

WITH m AS (
    SELECT c.department_key, c.month_start,
           CASE WHEN MONTH(c.month_start) >= 4 THEN YEAR(c.month_start) ELSE YEAR(c.month_start) - 1 END AS fy,
           SUM(c.fte) AS fte, SUM(c.paybill) AS paybill, COUNT(*) AS orgs
    FROM dw.v_pay_cell AS c
    WHERE c.cell_status = 'valid'
    GROUP BY c.department_key, c.month_start
),
y AS (
    SELECT department_key,
           CONCAT(fy, '-', RIGHT(CAST(fy + 1 AS varchar(4)), 2)) AS financial_year,
           COUNT(*) AS months_present, SUM(fte) AS fte_sum, SUM(paybill) AS paybill_sum,
           MIN(orgs) AS orgs_min, MAX(orgs) AS orgs_max
    FROM m
    GROUP BY department_key, fy
),
j AS (
    SELECT r.rule_id, y.financial_year, y.department_key, y.months_present, y.fte_sum,
           CAST(ROUND(CAST(y.fte_sum AS decimal(38, 10)) / y.months_present, 4) AS decimal(19, 4)) AS avg_fte,
           y.paybill_sum, y.orgs_min, y.orgs_max,
           CASE WHEN y.months_present >= r.min_months THEN 'participant' ELSE 'too_few_months' END AS status
    FROM authored.allocation_rule AS r
    JOIN y ON y.financial_year BETWEEN r.first_financial_year AND r.last_financial_year
),
t AS (
    SELECT rule_id, financial_year, SUM(avg_fte) AS all_fte, SUM(CASE WHEN status = 'participant' THEN avg_fte END) AS part_fte
    FROM j GROUP BY rule_id, financial_year
)
INSERT INTO audit.allocation_participation
    (rule_id, financial_year, department_key, months_present, fte_sum, avg_fte, paybill_sum_gbp, orgs_min, orgs_max, status, would_be_weight)
SELECT j.rule_id, j.financial_year, j.department_key, j.months_present, j.fte_sum, j.avg_fte, j.paybill_sum, j.orgs_min, j.orgs_max, j.status,
       CAST(CASE WHEN j.status = 'too_few_months' THEN j.avg_fte / (t.part_fte + j.avg_fte) END AS decimal(19, 10))
FROM j
JOIN t ON t.rule_id = j.rule_id AND t.financial_year = j.financial_year;
GO

CREATE TABLE dw.fact_allocation (
    rule_id               varchar(30)    NOT NULL,
    financial_year        varchar(7)     NOT NULL,
    department_key        int            NOT NULL,
    pool_key              int            NOT NULL,
    pool_amount           decimal(19,4)  NOT NULL,   -- GBP thousands: the pool of the year (the same on every row of the year)
    avg_fte               decimal(19,4)  NOT NULL,
    months_present        int            NOT NULL,
    weight                decimal(19,10) NOT NULL,   -- avg_fte over the sum of the participants' avg_fte
    allocated_amount      decimal(19,4)  NOT NULL,   -- GBP thousands, includes rounding_adjustment
    rounding_adjustment   decimal(19,4)  NOT NULL,   -- zero except on the participant with the largest full-time equivalent
    is_rounding_row       bit            NOT NULL,
    paybill_annualised    decimal(19,4)  NOT NULL,   -- GBP thousands
    CONSTRAINT pk_dw_fact_allocation PRIMARY KEY (rule_id, financial_year, department_key),
    CONSTRAINT fk_dw_fact_allocation_pool FOREIGN KEY (pool_key) REFERENCES dw.allocation_pool (pool_key)
);
GO

WITH p AS (
    SELECT a.rule_id, a.financial_year, a.department_key, a.months_present, a.avg_fte, a.paybill_sum_gbp,
           d.department_number, pl.pool_key, pl.pool_amount,
           CAST(ROUND(pl.pool_amount * 10000, 0) AS decimal(38, 0)) AS pool_t,
           CAST(ROUND(a.avg_fte * 10000, 0) AS decimal(38, 0)) AS fte_t
    FROM audit.allocation_participation AS a
    JOIN dw.dim_department AS d ON d.department_key = a.department_key
    JOIN dw.allocation_pool AS pl ON pl.rule_id = a.rule_id AND pl.financial_year = a.financial_year
    WHERE a.status = 'participant'
),
w AS (
    SELECT p.*, SUM(p.avg_fte) OVER (PARTITION BY p.rule_id, p.financial_year) AS total_fte,
           SUM(p.fte_t) OVER (PARTITION BY p.rule_id, p.financial_year) AS total_t,
           ROW_NUMBER() OVER (PARTITION BY p.rule_id, p.financial_year ORDER BY p.fte_t DESC, p.department_number) AS rank_no
    FROM p
),
x AS (
    SELECT w.*, ROUND(w.pool_t * w.fte_t / w.total_t, 0) AS alloc_t
    FROM w
),
z AS (
    SELECT x.*, x.pool_t - SUM(x.alloc_t) OVER (PARTITION BY x.rule_id, x.financial_year) AS remainder_t
    FROM x
)
INSERT INTO dw.fact_allocation
    (rule_id, financial_year, department_key, pool_key, pool_amount, avg_fte, months_present, weight, allocated_amount,
     rounding_adjustment, is_rounding_row, paybill_annualised)
SELECT z.rule_id, z.financial_year, z.department_key, z.pool_key, z.pool_amount, z.avg_fte, z.months_present,
       CAST(z.avg_fte / z.total_fte AS decimal(19, 10)),
       CAST((z.alloc_t + CASE WHEN z.rank_no = 1 THEN z.remainder_t ELSE 0 END) / 10000 AS decimal(19, 4)),
       CAST(CASE WHEN z.rank_no = 1 THEN z.remainder_t ELSE 0 END / 10000 AS decimal(19, 4)),
       CAST(CASE WHEN z.rank_no = 1 THEN 1 ELSE 0 END AS bit),
       CAST(ROUND(CAST(z.paybill_sum_gbp AS decimal(38, 10)) * 12 / (1000 * z.months_present), 4) AS decimal(19, 4))
FROM z;
GO

CREATE TABLE audit.allocation_year_summary (
    rule_id                        varchar(30)    NOT NULL,
    financial_year                 varchar(7)     NOT NULL,
    pool_amount                    decimal(19,4)  NOT NULL,
    participants                   int            NOT NULL,
    participant_fte                decimal(19,4)  NOT NULL,
    allocated_total                decimal(19,4)  NOT NULL,
    difference_to_pool             decimal(19,4)  NOT NULL,   -- allocated total less the pool: zero
    rounding_adjustment            decimal(19,4)  NOT NULL,   -- what the largest-weight row was moved by to make it zero
    too_few_months_departments     int            NOT NULL,   -- departments with some valid cells and fewer than the minimum months
    too_few_months_fte             decimal(19,4)  NOT NULL,
    too_few_months_weight_share    decimal(19,10) NOT NULL,   -- their share of the full-time equivalent had they taken part
    no_workforce_departments       int            NOT NULL,   -- live departments with no valid cell in the year (the pool department excluded)
    CONSTRAINT pk_audit_allocation_year_summary PRIMARY KEY (rule_id, financial_year)
);
GO

INSERT INTO audit.allocation_year_summary
    (rule_id, financial_year, pool_amount, participants, participant_fte, allocated_total, difference_to_pool, rounding_adjustment,
     too_few_months_departments, too_few_months_fte, too_few_months_weight_share, no_workforce_departments)
SELECT pl.rule_id, pl.financial_year, pl.pool_amount,
       COUNT(f.department_key), COALESCE(SUM(f.avg_fte), 0),
       COALESCE(SUM(f.allocated_amount), 0), COALESCE(SUM(f.allocated_amount), 0) - pl.pool_amount,
       COALESCE(SUM(f.rounding_adjustment), 0),
       (SELECT COUNT(*) FROM audit.allocation_participation AS a WHERE a.rule_id = pl.rule_id AND a.financial_year = pl.financial_year AND a.status = 'too_few_months'),
       COALESCE((SELECT SUM(a.avg_fte) FROM audit.allocation_participation AS a WHERE a.rule_id = pl.rule_id AND a.financial_year = pl.financial_year AND a.status = 'too_few_months'), 0),
       COALESCE((SELECT CAST(CAST(SUM(a.avg_fte) AS decimal(19, 4)) * 1.0000000000
                             / (SUM(a.avg_fte) + (SELECT SUM(g.avg_fte) FROM dw.fact_allocation AS g
                                                  WHERE g.rule_id = pl.rule_id AND g.financial_year = pl.financial_year)) AS decimal(19, 10))
                 FROM audit.allocation_participation AS a
                 WHERE a.rule_id = pl.rule_id AND a.financial_year = pl.financial_year AND a.status = 'too_few_months'), 0),
       (SELECT COUNT(*) FROM dw.dim_department AS d
        WHERE d.is_current = 1 AND d.member_type = 'Department' AND d.department_key <> pl.pool_department_key
          AND NOT EXISTS (SELECT 1 FROM audit.allocation_participation AS a
                          WHERE a.rule_id = pl.rule_id AND a.financial_year = pl.financial_year AND a.department_key = d.department_key))
FROM dw.allocation_pool AS pl
LEFT JOIN dw.fact_allocation AS f ON f.rule_id = pl.rule_id AND f.financial_year = pl.financial_year
GROUP BY pl.rule_id, pl.financial_year, pl.pool_amount, pl.pool_department_key;
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'DERIVED: the real pool of each allocation rule and year (the revision deltas of the real outturn of the pool department in the pool control budget detail), GBP thousands. Read only by its model view and the audit; no real total reads it.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'allocation_pool';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'DERIVED: my own allocation of the pool by payroll full-time equivalent, one row per rule, year and participating department, GBP thousands. Not a government figure; read only by its model view and the audit; no real total reads it.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'fact_allocation';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'DERIVED: which departments take part in each year of an allocation rule, their average full-time equivalent, and for a department left out the weight it would have had.',
    @level0type = N'SCHEMA', @level0name = N'audit', @level1type = N'TABLE', @level1name = N'allocation_participation';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'DERIVED: the tie of the allocated amounts to the pool for each rule and year (the difference is zero), the rounding adjustment, and who is left out and what it would have changed.',
    @level0type = N'SCHEMA', @level0name = N'audit', @level1type = N'TABLE', @level1name = N'allocation_year_summary';
GO
