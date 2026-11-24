# 0005. A Type 2 organisation dimension on a letter-prefix durable key, with authored overrides

## Status

Accepted

## Context

OSCAR identifies an organisation by a code such as `NDA084`: three letters and a three-digit department number. Over the
31 releases bodies move between departments, departments are renamed, merged and split, and the publisher flips between
spellings of the same name. A report on this data has to answer two different questions: which department reported a line
in the release in view ("as reported"), and where that line sits in today's structure ("current structure").
Keying on the name or on the whole code fails the first, and keying on the department fails the second.

The profile of the 31 releases found that the three-letter prefix is mostly a durable identity, with exceptions:

- 23 bodies moved department and kept their prefix (for example ACAS, `ACA084` to `ACA013`).
- Two prefixes are held by two different bodies at once (`UKG`, `DOH`), and `EHR` in June 2019 looks like a coding error.
- Ofcom changed its prefix for real (`OFC048` to `OCM084`).
- Three core-department codes were reused by a new department (`BIS084` BEIS then DSIT, the DIT core code then DBT, `DID030`
  DFID then FCDO), and `FCO027` merged into `DID030`.
- 43 of 51 department-name changes between consecutive releases are the same department under an alternating label.

## Decision

- **Departments are keyed on the three-digit department number**, never on a name. A name is a label, kept per naming
  period in `authored/department_name.csv`.
- **An organisation has a durable key**, the three-letter prefix of its code, unless a row of
  `authored/organisation_key_override.csv` covers that code in that release. The file has 14 rows (prefix collisions, one
  coding error, one prefix change, the reused codes and the merger), each with its evidence.
- **`dw.dim_organisation` is Type 2 by release.** A new version starts only when a tracked attribute really changes: the
  code (a move between departments changes the suffix), the department, or a real name change. A name that flips between
  spellings is an alias, not a new version. Versions tile the life of a key, so a body that drops out of some releases and
  comes back stays covered.
- The current-structure mapping is a separate step (`stg.current_structure_map`): it moves lines to the department of
  today's structure by rule, with 20 authored rows where the rules cannot decide, and it never changes an amount.

## Consequences

- "As reported" means "as the release in view reports it". Reorganisations show between releases and never inside one:
  each release puts an organisation under one department for all its months.
- The fact is keyed on the organisation version. A body that changes version inside a year reverses under the old key and
  appears under the new one (see [0004](0004-revision-deltas-not-stacked-snapshots.md)), which is what keeps the as-at amount
  equal to the release.
- The 14 overrides are my judgement and are visible: each is a row with a reason and evidence, and a test fails if one is
  malformed or unused. A new release that breaks the prefix rule in a way the overrides do not cover will be flagged by the
  tests, not absorbed silently.
- The version of an organisation a plan or a security rule needs is read by `Organisation Code` and `Durable Key`, which is
  why the restricted role cannot hide those two columns ([security.md](../security.md)).
- Whether the current-structure map is right is a separate question and has its own hold-out against the restated annual
  file, with its residuals published ([reconciliation.md](../reconciliation.md#known-residuals-published-not-hidden)).

## Evidence

- The profile and the candidate rows: [profiling/organisation-keys.md](../profiling/organisation-keys.md) (section 11),
  [profiling/data/org_durable_key_candidates.csv](../profiling/data/org_durable_key_candidates.csv).
- The authored files: [authored/organisation_key_override.csv](../../authored/organisation_key_override.csv),
  [authored/department_name.csv](../../authored/department_name.csv), registered in the README
  ([register](../../README.md#register-of-real-authored-derived-and-synthetic-data)).
- How the dimension is built and its row counts (409 rows: 408 versions and Unknown):
  [data-dictionary/organisation.md](../data-dictionary/organisation.md).
- **Tested** (committed scope, run by CI job `pipeline-sql`): overrides are well formed and every one is used
  (`sql/tests/210`, `211`), version ranges tile each durable key (`220`), every version start has a tracked change (`224`), name
  flips do not start versions (`225`), a department number has one label per release (`202`) and every published label
  belongs to its period (`205`). Assertion list: [reconciliation.md](../reconciliation.md#appendix-every-assertion).
