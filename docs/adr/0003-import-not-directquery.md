# 0003. Import mode, not DirectQuery

## Status

Accepted

## Context

The semantic model reads a SQL Server star schema that one command rebuilds from the files in git. The largest table,
`Fact Outturn`, has 658,554 rows; the other fact tables are far smaller. The model has to carry calculation groups,
window functions, row-level and object-level security and a plan grain guard, and every claim about it has to be
checkable on a laptop with Power BI Desktop and no service (see [0002](0002-power-bi-desktop-only.md)).

The two real choices were Import, or DirectQuery with Import aggregates (a composite model), which is the usual answer
when a fact is too large to import.

## Decision

All 33 tables of the model are Import, at compatibility level 1702. Each of the 16 SQL tables is one partition that
navigates to one view, `dw.v_model_<table>`, so the whole table is one `SELECT` of named columns and folds. I did not use
DirectQuery for any table.

## Consequences

- Data is held in Desktop's engine and is lost when Desktop closes, so every session starts with
  `tools/run_dax.ps1 -Refresh`. A change in the database is not seen until a refresh.
- Refresh is short on this data. **Tested**: the 16 SQL tables refreshed in 10.7 s the first time after Desktop opened and
  in 3.3 to 7.1 s after that ([model.md](../model.md#refresh); the tool prints the timings and I did not commit them as a
  result file).
- Queries are fast without any tuning of storage. **Tested**: the benchmark queries of the performance page run in
  13 to 259 ms cold (median of five runs) ([performance.md](../performance.md#the-timings-before-and-after)).
- I did not time DirectQuery on the real model, so "DirectQuery would be slower here" is a judgement from the size of
  the data and not a measurement. The sentence in [model.md](../model.md#decisions) that says so is **designed**, not
  tested.
- I did test the composite alternative on a throwaway model of about 2 million generated rows (DirectQuery detail,
  Import aggregate, Dual dimensions): an aggregation hit sends no SQL to the server, a miss sends SQL, and an aggregate
  column with the wrong data type loads without a warning and never hits. I did not keep that model, only its traces.
  The real model has no aggregations, so there is nothing of this kind to maintain. If a later phase loads a much
  larger fact (the `scale` schema is reserved for it and nothing is built), this decision has to be reopened.
- A refresh policy and incremental partitions are not used: Desktop never applies a refresh policy, and the real model
  has none (**tested**: `pipeline/tests/test_model_files.py`).

## Evidence

- Storage mode of every table: [evidence/model/reference/01_tables.csv](../../evidence/model/reference/01_tables.csv)
  (33 rows, all `Import`), listed in [model-reference.md](../model-reference.md).
- Every partition folds, from an Extended Events session during a refresh:
  [evidence/model/partition_queries.csv](../../evidence/model/partition_queries.csv).
- Timings and traces: [performance.md](../performance.md), [evidence/perf/](../../evidence/perf/).
- The composite-model spike, its traces and what an aggregation hit needs:
  [desktop_capabilities.md](../spikes/desktop_capabilities.md) (rows 9a to 9c and 10b) and
  [the spike evidence](../spikes/evidence/desktop/).
