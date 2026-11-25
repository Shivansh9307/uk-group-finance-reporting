# 0008. An evidence ledger that CI checks, instead of running the DAX tests in CI

## Status

Accepted

## Context

The DAX tests and the role cases run in Power BI Desktop against the model on my machine. A hosted CI runner has no
Analysis Services engine, and I do not use the service, Fabric or a self-hosted engine (see
[0002](0002-power-bi-desktop-only.md)). Without anything else, CI could not tell that a result file was stale, that an
expected file had been edited by hand, or that a measure had changed after the last run: the pull request would be green.

The options were to run the DAX in CI (not possible here), to trust the committed result files, or to make them
tamper-evident.

## Decision

`evidence/ledger.json` records, for one state of the repository, a hash of the model's projection (the TMDL with everything
Desktop and Tabular Editor rewrite on each save taken out), the sha256 of every DAX test, expected value, result, role
case and model-reference file, the build scope of each expected set, and the hash of `docs/model-reference.md`.

- `ukfr ledger write` refuses to write unless the DAX comparison passes for every test, the role-case comparison passes for
  every case, the expected values are full scope and the model reference was generated from the model as it is.
- The CI job `evidence-ledger` runs `ukfr ledger check` on a bare Python and fails when anything under the tracked folders
  has changed, when the model's hash differs, or when the model reference is stale.
- CI also regenerates the committed-scope expected values from a database built from the files in git, and requires them to
  be identical to the committed set.

## Consequences

- A measure edited without a rerun goes red. A changed result, expected file or test goes red. A change that only reorders
  objects, changes a lineage tag or a `PBI_*` annotation, or rewrites line endings does not, and should not.
- It is a ledger, not a rerun. It does not prove that a result file came from running the DAX against this model: if I
  edited a result by hand to equal the expected value and ran `ukfr ledger write`, the ledger would accept it. Running the
  steps in the stated order, straight after Desktop has loaded and refreshed the model, is my discipline, and a hosted
  runner cannot check it.
- The full-scope expected values are only hash-checked in CI, because the runner cannot build the full-scope database. They
  are the output of SQL I wrote against it. CI re-derives the committed-scope set only, which shows that the queries are
  stable, not that they are correct at full scope.
- Refreshing the evidence is a seven-step procedure in a fixed order, and it needs Desktop and the full-scope database
  ([evidence.md](../evidence.md#how-to-refresh-it)). That is the price of the check.
- A release workflow (`.github/workflows/release.yml`) runs the same check on a tag before it publishes. **Tested**: it ran
  once, on the tag `v1.0.0` on 2026-11-24, and every step succeeded ([run 45298915073](https://github.com/Shivansh9307/uk-group-finance-reporting/actions/runs/45298915073)); it has not run on
  any other tag.

## Evidence

- What the ledger holds, what CI checks, what it cannot prove: [evidence.md](../evidence.md).
- **Tested**: a red and a green run on the pull request branch. A commit that changed one measure's expression and nothing
  else failed only the `evidence-ledger` job; the commit that restored it passed all four jobs
  ([evidence.md](../evidence.md#the-red-and-the-green-run), with the run numbers and the text the job printed).
- **Tested**: the write gate, the check, the projection and the committed-scope set, in `pipeline/tests/test_ledger.py`
  (no database or Desktop needed).
- The ledger itself: [evidence/ledger.json](../../evidence/ledger.json); the comparisons it embeds:
  [evidence/model/dax_tests.csv](../../evidence/model/dax_tests.csv) (84 of 84),
  [evidence/model/rls_tests.csv](../../evidence/model/rls_tests.csv) (87 of 87).
