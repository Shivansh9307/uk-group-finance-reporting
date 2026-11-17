-- test: no row of the real releases is in quarantine
-- Profiling found no reject in the 31 releases. A row here means a release changed or the loader
-- rules need a decision; it is never dropped silently.

SELECT file_id, source_row, release, reason_code, reason_detail, amount_text, [month]
FROM quarantine.oscar_inyear;
