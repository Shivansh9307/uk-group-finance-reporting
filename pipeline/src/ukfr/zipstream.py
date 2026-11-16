"""Stream-read zip members, including Deflate64 (method 9), without extracting to disk.

The standard library reads the central directory (and ZIP64 sizes) but cannot decompress
Deflate64. For those members I read the raw compressed bytes from the local header onwards and
feed them through `inflate64.Inflater`.
"""

from __future__ import annotations

import io
import struct
import zipfile
import zlib
from collections.abc import Iterator
from pathlib import Path

import inflate64

STORED, DEFLATED, DEFLATE64 = 0, 8, 9
METHOD_NAMES = {STORED: "stored", DEFLATED: "deflate", DEFLATE64: "deflate64", 12: "bzip2", 14: "lzma"}
CHUNK = 1 << 20


def members(path: Path) -> list[zipfile.ZipInfo]:
    with zipfile.ZipFile(path) as z:
        return [i for i in z.infolist() if not i.is_dir()]


def describe(path: Path) -> str:
    """'name|method|uncompressed bytes' for each member, ';'-separated (for the manifest)."""
    return ";".join(
        f"{i.filename}|{METHOD_NAMES.get(i.compress_type, str(i.compress_type))}|{i.file_size}" for i in members(path)
    )


def _data_offset(f, info: zipfile.ZipInfo) -> int:
    f.seek(info.header_offset)
    header = f.read(30)
    sig, *_rest = struct.unpack("<4s26s", header)
    if sig != b"PK\x03\x04":
        raise zipfile.BadZipFile(f"bad local header for {info.filename}")
    name_len, extra_len = struct.unpack("<HH", header[26:30])
    return info.header_offset + 30 + name_len + extra_len


def iter_member(path: Path, name: str) -> Iterator[bytes]:
    """Yield the decompressed bytes of one member in chunks."""
    with zipfile.ZipFile(path) as z:
        info = z.getinfo(name)
    if info.flag_bits & 0x1:
        raise zipfile.BadZipFile(f"{name} is encrypted")
    with open(path, "rb") as f:
        f.seek(_data_offset(f, info))
        remaining = info.compress_size
        flush = None
        if info.compress_type == STORED:
            step = bytes
        elif info.compress_type == DEFLATED:
            z = zlib.decompressobj(-15)
            step, flush = z.decompress, z.flush
        elif info.compress_type == DEFLATE64:
            step = inflate64.Inflater().inflate
        else:
            raise NotImplementedError(f"{name}: zip method {info.compress_type}")
        while remaining > 0:
            raw = f.read(min(CHUNK, remaining))
            if not raw:
                raise zipfile.BadZipFile(f"{name}: truncated")
            remaining -= len(raw)
            out = step(raw)
            if out:
                yield out
        if flush is not None:
            tail = flush()
            if tail:
                yield tail


class _ChunkReader(io.RawIOBase):
    def __init__(self, chunks: Iterator[bytes]):
        self._chunks = chunks
        self._buf = b""

    def readable(self) -> bool:
        return True

    def close(self) -> None:
        close = getattr(self._chunks, "close", None)
        if close:
            close()
        super().close()

    def readinto(self, b) -> int:
        while not self._buf:
            try:
                self._buf = next(self._chunks)
            except StopIteration:
                return 0
        n = min(len(b), len(self._buf))
        b[:n] = self._buf[:n]
        self._buf = self._buf[n:]
        return n


def open_text(path: Path, name: str, encoding: str = "utf-8", errors: str = "strict") -> io.TextIOWrapper:
    """A text stream over one member; only what is read is decompressed."""
    raw = io.BufferedReader(_ChunkReader(iter_member(path, name)), buffer_size=CHUNK)
    return io.TextIOWrapper(raw, encoding=encoding, errors=errors, newline="")


def head_lines(path: Path, name: str, n: int, encoding: str = "utf-8", errors: str = "replace") -> list[str]:
    out = []
    with open_text(path, name, encoding=encoding, errors=errors) as t:
        for line in t:
            out.append(line.rstrip("\r\n"))
            if len(out) >= n:
                break
    return out
