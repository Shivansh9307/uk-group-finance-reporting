-- test: no BUD or PSS row is quarantined
-- marker: localdata
-- requires: quarantine.oscar_bud, quarantine.pss
SELECT N'quarantine.oscar_bud' AS tbl, file_id, source_row, reason_code FROM quarantine.oscar_bud
UNION ALL
SELECT N'quarantine.pss', file_id, source_row, reason_code FROM quarantine.pss;
