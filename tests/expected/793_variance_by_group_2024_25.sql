-- Independent of the model, for the two measures the report filter keeps (resource DEL excluding depreciation, capital DEL): per Spending Review group, the plan (rows that are not part of another measure) and the
-- in-year plan-basis outturn at the last release of 2024-25 for the measures the group has a plan row for. Groups with
-- no plan do not appear; a group with a plan and no outturn (the Single Intelligence Account) has no outturn and so no variance. The waterfall columns repeat the plan and the outturn.
WITH pl AS (
    SELECT sr_group_key, measure, SUM(amount) AS plan_amount
    FROM dw.fact_plan
    WHERE financial_year = '2024-25' AND is_part_of_other_measure = 0 AND measure IN ('RDEL_EX_DEPN', 'CDEL')
    GROUP BY sr_group_key, measure
), ob AS (
    SELECT b.sr_group_key, b.measure, SUM(b.amount) AS basis_amount
    FROM dw.outturn_plan_basis_inyear AS b
    WHERE b.financial_year = '2024-25'
      AND b.release_key = (SELECT MAX(r.release_key) FROM dw.dim_release AS r WHERE r.financial_year = '2024-25')
    GROUP BY b.sr_group_key, b.measure
), x AS (
    SELECT pl.sr_group_key, SUM(pl.plan_amount) AS plan_amount, SUM(ob.basis_amount) AS basis_amount
    FROM pl LEFT JOIN ob ON ob.sr_group_key = pl.sr_group_key AND ob.measure = pl.measure
    GROUP BY pl.sr_group_key
)
SELECT g.sr_group_name AS [group], CAST(x.basis_amount AS decimal(38, 4)) AS outturn_plan_basis, CAST(x.plan_amount AS decimal(38, 4)) AS [plan],
       CAST(x.basis_amount - x.plan_amount AS decimal(38, 4)) AS variance,
       CAST(CASE WHEN x.plan_amount <> 0 THEN (x.basis_amount - x.plan_amount) * 1000000 / ABS(x.plan_amount) END AS decimal(38, 4)) AS variance_ppm,
       CAST(x.plan_amount AS decimal(38, 4)) AS waterfall_plan, CAST(x.basis_amount AS decimal(38, 4)) AS waterfall_outturn
FROM x JOIN dw.dim_sr_group AS g ON g.sr_group_key = x.sr_group_key
ORDER BY g.sr_group_name;
