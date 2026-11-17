"""SQL Server connection settings and a thin wrapper over the `mssql-python` driver.

Settings come from environment variables, with local defaults:

| variable                        | default            | meaning                                           |
|---------------------------------|--------------------|---------------------------------------------------|
| `UKFR_SQL_SERVER`               | `localhost`        | server, or `host,port`                            |
| `UKFR_SQL_DATABASE`             | `UKGroupFinance`   | database the build creates and fills              |
| `UKFR_SQL_USER`                 | (empty)            | empty = Windows integrated authentication         |
| `UKFR_SQL_PASSWORD`             | (empty)            | used only with `UKFR_SQL_USER` (SQL authentication) |
| `UKFR_SQL_ENCRYPT`              | `yes`              | `yes` or `no`                                     |
| `UKFR_SQL_TRUST_SERVER_CERT`    | `yes`              | accept a self-signed server certificate           |
| `UKFR_SQL_LOADER`               | `bulk`             | `bulk` (driver bulk copy) or `executemany`        |
"""

from __future__ import annotations

import os
import time
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, field, replace
from typing import Any

ENV_SERVER = "UKFR_SQL_SERVER"
ENV_DATABASE = "UKFR_SQL_DATABASE"
ENV_USER = "UKFR_SQL_USER"
ENV_PASSWORD = "UKFR_SQL_PASSWORD"
ENV_ENCRYPT = "UKFR_SQL_ENCRYPT"
ENV_TRUST = "UKFR_SQL_TRUST_SERVER_CERT"
ENV_LOADER = "UKFR_SQL_LOADER"

DEFAULT_DATABASE = "UKGroupFinance"
SCHEMAS = ("raw", "stg", "dw", "authored", "synthetic", "scale", "quarantine", "audit")


def _yes(value: str, name: str) -> bool:
    v = value.strip().lower()
    if v in ("yes", "true", "1", "y"):
        return True
    if v in ("no", "false", "0", "n"):
        return False
    raise ValueError(f"{name} must be yes or no, got {value!r}")


def _quote_value(value: str) -> str:
    """Connection-string value: braces protect `;`, `{` and `}`."""
    if any(c in value for c in ";{}") or value != value.strip():
        return "{" + value.replace("}", "}}") + "}"
    return value


@dataclass(frozen=True)
class DbSettings:
    server: str = "localhost"
    database: str = DEFAULT_DATABASE
    user: str = ""
    password: str = field(default="", repr=False)
    encrypt: bool = True
    trust_server_certificate: bool = True
    loader: str = "bulk"

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> DbSettings:
        e = os.environ if env is None else env
        loader = e.get(ENV_LOADER, "bulk").strip().lower()
        if loader not in ("bulk", "executemany"):
            raise ValueError(f"{ENV_LOADER} must be bulk or executemany, got {loader!r}")
        return cls(
            server=e.get(ENV_SERVER, "localhost").strip() or "localhost",
            database=e.get(ENV_DATABASE, DEFAULT_DATABASE).strip() or DEFAULT_DATABASE,
            user=e.get(ENV_USER, "").strip(),
            password=e.get(ENV_PASSWORD, ""),
            encrypt=_yes(e.get(ENV_ENCRYPT, "yes"), ENV_ENCRYPT),
            trust_server_certificate=_yes(e.get(ENV_TRUST, "yes"), ENV_TRUST),
            loader=loader,
        )

    @property
    def auth_mode(self) -> str:
        """'sql' when a user is set, otherwise 'windows' (integrated authentication)."""
        return "sql" if self.user else "windows"

    def with_database(self, database: str) -> DbSettings:
        return replace(self, database=database)

    def connection_string(self) -> str:
        parts = [f"Server={_quote_value(self.server)}", f"Database={_quote_value(self.database)}"]
        if self.user:
            parts += [f"UID={_quote_value(self.user)}", f"PWD={_quote_value(self.password)}"]
        else:
            parts.append("Trusted_Connection=yes")
        parts.append(f"Encrypt={'yes' if self.encrypt else 'no'}")
        parts.append(f"TrustServerCertificate={'yes' if self.trust_server_certificate else 'no'}")
        return ";".join(parts) + ";"

    def describe(self) -> str:
        """For logs: never contains the password."""
        who = f"SQL login {self.user}" if self.user else "Windows integrated authentication"
        return f"{self.server} / {self.database} ({who})"


def quote_name(name: str) -> str:
    """Bracket-quote one SQL identifier."""
    return "[" + name.replace("]", "]]") + "]"


class Db:
    """One autocommit connection. Every call drains its result sets, so errors raised late in a
    multi-statement batch surface here instead of being lost."""

    def __init__(self, settings: DbSettings, login_timeout: int = 30) -> None:
        import mssql_python

        self.settings = settings
        self.conn = mssql_python.connect(settings.connection_string(), autocommit=True, timeout=login_timeout)
        self._exec("SET NOCOUNT ON")

    # -- running SQL ---------------------------------------------------------------------------
    def _exec(self, sql: str, params: Sequence[Any] = ()) -> list[tuple]:
        cur = self.conn.cursor()
        try:
            cur.execute(sql, tuple(params)) if params else cur.execute(sql)
            rows: list[tuple] = []
            while True:
                if cur.description is not None:
                    rows.extend(tuple(r) for r in cur.fetchall())
                if not cur.nextset():
                    break
            return rows
        finally:
            cur.close()

    def execute(self, sql: str, params: Sequence[Any] = ()) -> None:
        self._exec(sql, params)

    def query(self, sql: str, params: Sequence[Any] = ()) -> list[tuple]:
        return self._exec(sql, params)

    def scalar(self, sql: str, params: Sequence[Any] = ()) -> Any:
        rows = self._exec(sql, params)
        return rows[0][0] if rows else None

    def columns(self, sql: str) -> tuple[list[str], list[tuple]]:
        """Column names and rows of one query."""
        cur = self.conn.cursor()
        try:
            cur.execute(sql)
            names = [d[0] for d in cur.description]
            return names, [tuple(r) for r in cur.fetchall()]
        finally:
            cur.close()

    # -- loading -------------------------------------------------------------------------------
    def insert_many(self, table: str, columns: Sequence[str], rows: Iterable[Sequence[Any]]) -> int:
        """Insert rows; returns the number inserted. `table` is `schema.name` (already safe SQL).

        With the `bulk` loader this is the driver's bulk copy, which validates string lengths
        client side and fails the whole call on a bad value. With `executemany` it is a parameter
        array in chunks, slower but with the plain insert path.
        """
        if self.settings.loader == "bulk":
            result = self._bulk(table, columns, rows)
            return int(result["rows_copied"])
        cols = ", ".join(quote_name(c) for c in columns)
        marks = ", ".join("?" for _ in columns)
        sql = f"INSERT INTO {table} ({cols}) VALUES ({marks})"
        total = 0
        chunk: list[tuple] = []
        cur = self.conn.cursor()
        try:
            for row in rows:
                chunk.append(tuple(row))
                if len(chunk) >= 5000:
                    cur.executemany(sql, chunk)
                    total += len(chunk)
                    chunk = []
            if chunk:
                cur.executemany(sql, chunk)
                total += len(chunk)
        finally:
            cur.close()
        return total

    def _bulk(self, table: str, columns: Sequence[str], rows: Iterable[Sequence[Any]]) -> dict:
        cur = self.conn.cursor()
        try:
            return cur.bulkcopy(
                table,
                (tuple(r) for r in rows),
                batch_size=100_000,
                timeout=0,
                column_mappings=list(columns),
                table_lock=True,
            )
        finally:
            cur.close()

    def close(self) -> None:
        try:
            self.conn.close()
        except Exception:  # pragma: no cover - closing a dead connection
            pass

    def __enter__(self) -> Db:
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()


def wait_for_server(settings: DbSettings, seconds: float, log=print) -> None:
    """Retry a login to `master` until it works or `seconds` pass (a container is slow to accept logins)."""
    deadline = time.monotonic() + seconds
    attempt = 0
    while True:
        attempt += 1
        try:
            Db(settings.with_database("master"), login_timeout=5).close()
            if attempt > 1:
                log(f"  server accepted a login on attempt {attempt}")
            return
        except Exception as exc:
            if time.monotonic() >= deadline:
                raise RuntimeError(f"no login to {settings.describe()} within {seconds:.0f} s: {exc}") from exc
            time.sleep(2)


def database_exists(db: Db, name: str) -> bool:
    return db.scalar("SELECT DB_ID(?)", (name,)) is not None
