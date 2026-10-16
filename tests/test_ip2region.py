#!/usr/bin/env python3
"""Small synthetic XDB fixture test for the Lua 5.1 IPv4 lookup helper."""
import pathlib
import struct
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "root/usr/share/wechatpush/ip2region.lua"
IP = "1.2.3.4"
REGION = "中国|北京|北京|电信|CN".encode("utf-8")

with tempfile.TemporaryDirectory() as tmp:
    db = pathlib.Path(tmp) / "test.xdb"
    header = bytearray(256)
    struct.pack_into("<H", header, 0, 2)  # XDB structure v2, IPv4
    vector = bytearray(256 * 256 * 8)

    segment_ptr = len(header) + len(vector)
    data_ptr = segment_ptr + 14
    ip_value = (1 << 24) | (2 << 16) | (3 << 8) | 4
    segment = (
        struct.pack("<I", ip_value)
        + struct.pack("<I", ip_value)
        + struct.pack("<H", len(REGION))
        + struct.pack("<I", data_ptr)
    )
    vector_offset = (1 * 256 + 2) * 8
    struct.pack_into("<II", vector, vector_offset, segment_ptr, segment_ptr)
    db.write_bytes(header + vector + segment + REGION)

    result = subprocess.run(
        ["lua5.1", str(HELPER), str(db), IP],
        check=True, capture_output=True, text=True,
    )
    assert result.stdout == "中国 北京 北京 电信 CN", result.stdout

    missing = subprocess.run(
        ["lua5.1", str(HELPER), str(db), "1.2.3.5"],
        capture_output=True, text=True,
    )
    assert missing.returncode != 0 and not missing.stdout, (
        missing.returncode, missing.stdout, missing.stderr
    )

print("ip2region Lua XDB fixture test passed")
