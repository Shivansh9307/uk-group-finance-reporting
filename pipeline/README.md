# ukfr pipeline

Python package for fetching the published sources and loading them into SQL Server. Run it from the repository root:

```
uv run --project pipeline ukfr fetch            # discover and download everything in data/manifest/sources.yml
uv run --project pipeline ukfr fetch --verify   # offline sha256 check against data/manifest/files.csv
uv run --project pipeline ukfr build            # create the database, load, run sql/, write evidence/build
uv run --project pipeline pytest -q             # tests (no network; database tests need a built database)
```

`build` and the tests read `UKFR_SQL_*` environment variables (server, database, optional SQL login);
see [docs/pipeline.md](../docs/pipeline.md).

See [docs/data-sources.md](../docs/data-sources.md) for the sources and how discovery works.
