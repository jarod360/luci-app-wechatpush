#!/usr/bin/env python3
"""Synthetic XDB fixture tests for the Lua 5.1 IPv4 lookup helper."""
import pathlib
import struct
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "root/usr/share/wechatpush/ip2region.lua"
IP = "1.2.3.4"


def write_xdb(path, region):
    region = region.encode("utf-8")
    header = bytearray(256)
    struct.pack_into("<H", header, 0, 2)  # XDB structure v2, IPv4
    vector = bytearray(256 * 256 * 8)

    segment_ptr = len(header) + len(vector)
    data_ptr = segment_ptr + 14
    ip_value = (1 << 24) | (2 << 16) | (3 << 8) | 4
    segment = (
        struct.pack("<I", ip_value)
        + struct.pack("<I", ip_value)
        + struct.pack("<H", len(region))
        + struct.pack("<I", data_ptr)
    )
    vector_offset = (1 * 256 + 2) * 8
    struct.pack_into("<II", vector, vector_offset, segment_ptr, segment_ptr)
    path.write_bytes(header + vector + segment + region)


def lookup(path, ip=IP):
    return subprocess.run(
        ["lua5.1", str(HELPER), str(path), ip],
        capture_output=True, text=True,
    )


with tempfile.TemporaryDirectory() as tmp:
    tmp = pathlib.Path(tmp)

    # Legacy format without a continent field remains unchanged.
    legacy_db = tmp / "legacy.xdb"
    write_xdb(legacy_db, "中国|北京|北京|电信|CN")
    result = lookup(legacy_db)
    assert result.returncode == 0
    assert result.stdout == "北京", result.stdout

    # Mainland records: omit continent and county, retain city and ISP.
    mainland_db = tmp / "mainland.xdb"
    write_xdb(mainland_db, "亚洲|中国|宁夏回族自治区|中卫市|海原县|联通")
    result = lookup(mainland_db)
    assert result.returncode == 0
    assert result.stdout == "中卫市", result.stdout

    # Hong Kong records: omit continent and district, retain city and ASN.
    hong_kong_db = tmp / "hong-kong.xdb"
    write_xdb(
        hong_kong_db,
        "亚洲|中国香港|Kwai Tsing District|葵涌|DMIT Cloud Services AS906",
    )
    result = lookup(hong_kong_db)
    assert result.returncode == 0
    assert result.stdout == "中国香港 葵涌", result.stdout

    # Foreign locations retain country and city, but omit province/district and ASN.
    foreign_db = tmp / "foreign.xdb"
    write_xdb(
        foreign_db,
        "Europe|United States|California|Los Angeles|Los Angeles County|Example ISP AS123",
    )
    result = lookup(foreign_db)
    assert result.returncode == 0
    assert result.stdout == "United States Los Angeles", result.stdout

    missing = lookup(legacy_db, "1.2.3.5")
    assert missing.returncode != 0 and not missing.stdout, (
        missing.returncode, missing.stdout, missing.stderr
    )

print("ip2region Lua XDB fixture tests passed")
