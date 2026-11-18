-- audit.sr_group_bridge_summary: what the outturn-to-Spending-Review-group bridge did, one row per group.
-- Pairs are (organisation version, sub-segment) pairs of dw.outturn_sr_group_bridge; exception pairs are the ones
-- an organisation exception of authored/department_sr_group.csv decided.

DROP TABLE IF EXISTS audit.sr_group_bridge_summary;
GO

CREATE TABLE audit.sr_group_bridge_summary (
    sr_group_code       varchar(20)    NOT NULL CONSTRAINT pk_audit_sr_group_bridge_summary PRIMARY KEY,
    sr_group_name       nvarchar(200)  NOT NULL,
    department_numbers  nvarchar(400)  NOT NULL,
    pairs               int            NOT NULL,
    organisation_codes  int            NOT NULL,
    exception_pairs     int            NOT NULL
);
GO

INSERT INTO audit.sr_group_bridge_summary (sr_group_code, sr_group_name, department_numbers, pairs, organisation_codes, exception_pairs)
SELECT g.sr_group_code, g.sr_group_name,
       (SELECT STRING_AGG(x.department_number, ' ') WITHIN GROUP (ORDER BY x.department_number)
        FROM (SELECT DISTINCT b2.department_number FROM dw.outturn_sr_group_bridge AS b2 WHERE b2.sr_group_key = g.sr_group_key) AS x),
       COUNT(*),
       COUNT(DISTINCT o.organisation_code),
       SUM(CASE WHEN b.bridge_rule = 'organisation exception' THEN 1 ELSE 0 END)
FROM dw.outturn_sr_group_bridge AS b
JOIN dw.dim_sr_group AS g ON g.sr_group_key = b.sr_group_key
JOIN dw.dim_organisation AS o ON o.organisation_key = b.organisation_key
GROUP BY g.sr_group_key, g.sr_group_code, g.sr_group_name;
GO
