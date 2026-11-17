-- phase: pre
-- Landing table for docs/profiling/data/inyear_delta_rowcount.csv (written by ukfr.stages.profile_controls).
-- Text exactly as in the file; the comparison with the warehouse is audit.delta_rowcount.
-- Safe to run again: created only if missing.

IF OBJECT_ID(N'raw.profile_inyear_delta_rowcount', N'U') IS NULL
CREATE TABLE raw.profile_inyear_delta_rowcount (
    financial_year       varchar(7)   NOT NULL,
    release              varchar(7)   NOT NULL CONSTRAINT pk_raw_profile_inyear_delta_rowcount PRIMARY KEY,
    release_no_in_year   varchar(10)  NOT NULL,
    stacked_keys         varchar(20)  NOT NULL,
    first_appearances    varchar(20)  NOT NULL,
    changed              varchar(20)  NOT NULL,
    vanished             varchar(20)  NOT NULL,
    delta_rows_all       varchar(20)  NOT NULL,
    delta_rows_non_zero  varchar(20)  NOT NULL
);
GO
