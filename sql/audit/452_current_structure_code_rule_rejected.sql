-- audit.current_structure_code_rule_rejected: the lines where I did not follow the sub-segment code.
--   The code rule (dw.current_structure_line) is applied only to an organisation whose own department no
--   longer exists. For an organisation that still has a home, a few lines would go elsewhere if the rule
--   were applied to it: the latest release that publishes the sub-segment code reports it under another
--   current department than the one the organisation is in now. Those lines are listed here with both
--   departments, so the choice can be reviewed. Grain: organisation version and sub-segment code.
--   code_release          the latest release that publishes the code
--   code_organisation     the organisation code that publishes it there
--   Lines that an authored row already decides are left out.

DROP TABLE IF EXISTS audit.current_structure_code_rule_rejected;
GO

CREATE TABLE audit.current_structure_code_rule_rejected (
    organisation_key              int           NOT NULL,
    sub_segment_code              nvarchar(50)  NOT NULL,
    organisation_code             nvarchar(50)  NOT NULL,
    code_release                  varchar(7)    NOT NULL,
    code_organisation_code        nvarchar(50)  NOT NULL,
    code_department_number        nvarchar(10)  NOT NULL,
    code_department_name          nvarchar(400) NOT NULL,
    chosen_department_number      nvarchar(10)  NOT NULL,
    chosen_department_name        nvarchar(400) NOT NULL,
    method                        varchar(40)   NOT NULL,
    CONSTRAINT pk_audit_current_structure_code_rule_rejected PRIMARY KEY (organisation_key, sub_segment_code, code_organisation_code)
);
GO

WITH last_seq AS (
    SELECT s.sub_segment_code, MAX(r.release_seq) AS last_seq
    FROM stg.inyear_snapshot AS s JOIN stg.release AS r ON r.release = s.release
    GROUP BY s.sub_segment_code
), at_last AS (
    SELECT DISTINCT ls.sub_segment_code, r.release, m.organisation_code, m.department_key
    FROM last_seq AS ls
    JOIN stg.release AS r ON r.release_seq = ls.last_seq
    JOIN stg.inyear_snapshot AS s ON s.release = r.release AND s.sub_segment_code = ls.sub_segment_code
    JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
)
INSERT INTO audit.current_structure_code_rule_rejected
SELECT l.organisation_key, l.sub_segment_code, o.organisation_code, a.release, a.organisation_code,
       ad.department_number, ad.department_name, cd.department_number, cd.department_name, l.method
FROM dw.current_structure_line AS l
JOIN dw.dim_organisation AS o ON o.organisation_key = l.organisation_key
JOIN at_last AS a ON a.sub_segment_code = l.sub_segment_code
JOIN dw.dim_department AS ad ON ad.department_key = a.department_key
JOIN dw.dim_department AS cd ON cd.department_key = l.current_department_key
WHERE l.method = 'organisation current department'
  AND ad.is_current = 1 AND ad.member_type = 'Department'
  AND ad.department_number <> cd.department_number;
GO
