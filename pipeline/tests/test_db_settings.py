"""Connection settings from the environment (no database)."""

from __future__ import annotations

import pytest

from ukfr.db import DbSettings


def test_defaults_are_local_windows_authentication():
    s = DbSettings.from_env({})
    assert (s.server, s.database, s.auth_mode, s.loader) == ("localhost", "UKGroupFinance", "windows", "bulk")
    cs = s.connection_string()
    assert "Trusted_Connection=yes" in cs and "UID=" not in cs and "PWD=" not in cs
    assert "Server=localhost;" in cs and "Database=UKGroupFinance;" in cs
    assert "Encrypt=yes" in cs and "TrustServerCertificate=yes" in cs


def test_a_user_switches_to_sql_authentication_and_the_password_is_never_shown():
    s = DbSettings.from_env(
        {
            "UKFR_SQL_SERVER": "localhost,1433",
            "UKFR_SQL_DATABASE": "Scratch",
            "UKFR_SQL_USER": "sa",
            "UKFR_SQL_PASSWORD": "s3cret;}x",
        }
    )
    assert s.auth_mode == "sql"
    cs = s.connection_string()
    assert "Trusted_Connection" not in cs
    assert "UID=sa;" in cs and "PWD={s3cret;}}x};" in cs  # braces protect ; and }
    assert "s3cret" not in repr(s) and "s3cret" not in s.describe()
    assert s.describe() == "localhost,1433 / Scratch (SQL login sa)"


def test_with_database_keeps_the_rest():
    s = DbSettings.from_env({"UKFR_SQL_USER": "sa", "UKFR_SQL_PASSWORD": "x"}).with_database("master")
    assert s.database == "master" and s.user == "sa" and s.password == "x"


@pytest.mark.parametrize(
    "env",
    [{"UKFR_SQL_ENCRYPT": "maybe"}, {"UKFR_SQL_TRUST_SERVER_CERT": "2"}, {"UKFR_SQL_LOADER": "bcp"}],
)
def test_bad_values_are_rejected(env):
    with pytest.raises(ValueError):
        DbSettings.from_env(env)


def test_the_encrypt_and_trust_switches():
    s = DbSettings.from_env({"UKFR_SQL_ENCRYPT": "no", "UKFR_SQL_TRUST_SERVER_CERT": "no"})
    assert "Encrypt=no" in s.connection_string() and "TrustServerCertificate=no" in s.connection_string()
