-- test: PESA 2026 restates the outturn of the same years against PESA December 2025 with resource DEL lower and departmental resource AME higher by nearly the same amount (within 10%), so its AME is not on the framework of the plans of earlier editions
-- marker: localdata
-- requires: audit.pesa_2026_basis_change
SELECT 'PESA 2026 does not move resource DEL into resource AME' AS problem, d.financial_year AS detail,
       CONCAT(d.change, ' and ', a.change) AS detail2
FROM audit.pesa_2026_basis_change AS d
JOIN audit.pesa_2026_basis_change AS a ON a.financial_year = d.financial_year AND a.measure = 'RAME'
WHERE d.measure = 'RDEL'
  AND NOT (d.change < 0 AND a.change > 0 AND ABS(d.change + a.change) <= 0.1 * ABS(d.change))
UNION ALL
SELECT 'PESA 2026 basis change has no resource DEL row', 'none', NULL
WHERE NOT EXISTS (SELECT 1 FROM audit.pesa_2026_basis_change WHERE measure = 'RDEL');
