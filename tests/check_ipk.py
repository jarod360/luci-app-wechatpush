#!/usr/bin/env python3
"""Verify actual legacy SDK package version and non-minified runtime assets."""
import io
import pathlib
import re
import sys
import tarfile

packages, source = map(pathlib.Path, sys.argv[1:3])
makefile = (source / 'Makefile').read_text(encoding='utf-8')
version = re.search(r'^PKG_VERSION:=(.+)$', makefile, re.M)[1]
revision = re.search(r'^PKG_RELEASE:=(.+)$', makefile, re.M)[1]
expected = version + '-r' + revision
files = list(packages.rglob('luci-app-wechatpush_*.ipk'))
assert len(files) == 1, files
with tarfile.open(files[0]) as outer:
    archives = {pathlib.PurePosixPath(m.name).name: outer.extractfile(m).read()
                for m in outer.getmembers() if m.isfile()}
with tarfile.open(fileobj=io.BytesIO(archives['control.tar.gz'])) as control:
    member = next(m for m in control.getmembers() if m.name.lstrip('./') == 'control')
    metadata = control.extractfile(member).read().decode()
    assert re.search(r'^Version: (.+)$', metadata, re.M)[1] == expected, metadata
with tarfile.open(fileobj=io.BytesIO(archives['data.tar.gz'])) as data:
    members = {m.name.lstrip('./'): m for m in data.getmembers() if m.isfile()}
    for relative in ('usr/share/wechatpush/wechatpush', 'usr/share/wechatpush/tplink_api.lua',
                     'usr/share/wechatpush/ip2region.lua', 'usr/share/wechatpush/api/logo.jpg'):
        wanted = (source / 'root' / relative).read_bytes()
        if not relative.endswith('.jpg'):
            wanted = wanted.replace(b'\r\n', b'\n')
        assert data.extractfile(members[relative]).read() == wanted, relative
    assert members['usr/share/wechatpush/wechatpush'].mode & 0o111
print('PASS: IPK version', expected, 'and runtime/image assets match this commit')
