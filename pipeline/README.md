# ukfr pipeline

Python package for fetching the published sources. Run it from the repository root:

```
uv run --project pipeline ukfr fetch            # discover and download everything in data/manifest/sources.yml
uv run --project pipeline ukfr fetch --verify   # offline sha256 check against data/manifest/files.csv
uv run --project pipeline pytest -q             # tests (no network)
```

See [docs/data-sources.md](../docs/data-sources.md) for the sources and how discovery works.
