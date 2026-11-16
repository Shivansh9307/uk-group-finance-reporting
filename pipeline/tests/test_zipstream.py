"""Deflate64 (zip method 9) streaming, on a small zip built by hand in the test."""

import struct
import zipfile
import zlib

import inflate64

from ukfr import zipstream


def deflate64_zip(path, name: str, data: bytes) -> None:
    """Write a one-member zip whose member is compressed with Deflate64 (method 9)."""
    d = inflate64.Deflater()
    comp = d.deflate(data) + d.flush()
    crc = zlib.crc32(data)
    fname = name.encode()
    local = struct.pack("<4sHHHHHIIIHH", b"PK\x03\x04", 21, 0, 9, 0, 0, crc, len(comp), len(data), len(fname), 0)
    central = struct.pack(
        "<4sHHHHHHIIIHHHHHII",
        b"PK\x01\x02",
        21,
        21,
        0,
        9,
        0,
        0,
        crc,
        len(comp),
        len(data),
        len(fname),
        0,
        0,
        0,
        0,
        0,
        0,
    )
    body = local + fname + comp
    cd = central + fname
    eocd = struct.pack("<4sHHHHIIH", b"PK\x05\x06", 0, 0, 1, 1, len(cd), len(body), 0)
    path.write_bytes(body + cd + eocd)


def sample(n: int) -> bytes:
    return b"".join(f"ORG{i:05d}|Department {i % 37}|{i * 13}\r\n".encode() for i in range(n))


def test_deflate64_member_streams_lines(tmp_path):
    p = tmp_path / "extract.zip"
    data = sample(50_000)
    deflate64_zip(p, "extract.txt", data)
    info = zipstream.members(p)[0]
    assert info.compress_type == 9
    assert zipstream.describe(p) == f"extract.txt|deflate64|{len(data)}"
    assert zipstream.head_lines(p, "extract.txt", 3) == [
        "ORG00000|Department 0|0",
        "ORG00001|Department 1|13",
        "ORG00002|Department 2|26",
    ]
    assert b"".join(zipstream.iter_member(p, "extract.txt")) == data


def test_deflate_and_stored_members_match_stdlib(tmp_path):
    p = tmp_path / "plain.zip"
    data = sample(2_000)
    with zipfile.ZipFile(p, "w") as z:
        z.writestr("a.csv", data, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("b.csv", data, compress_type=zipfile.ZIP_STORED)
    for name in ("a.csv", "b.csv"):
        assert b"".join(zipstream.iter_member(p, name)) == data
    assert zipstream.describe(p) == f"a.csv|deflate|{len(data)};b.csv|stored|{len(data)}"
