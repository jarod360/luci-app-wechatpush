#!/bin/bash
source_file="${1:-root/usr/share/wechatpush/wechatpush}"
testdir=$(mktemp -d) || exit 1
trap 'rm -f "$testdir/functions.sh" "$testdir/aliases"; rmdir "$testdir"' EXIT
sed -n '/^getname() {/,/^}/p' "$source_file" > "$testdir/functions.sh"
. "$testdir/functions.sh"
process_and_check() { [ -n "$1" ] || return 1; printf '%s' "$1"; }
device_aliases_path="$testdir/aliases"
printf '%s\n' '192.0.2.10 Wrong prefix' '192.0.2.1 IP fallback' 'AA-BB-CC-DD-EE-FF 手机 100% "别名"' > "$device_aliases_path"
[ "$(getname 192.0.2.1 aa:bb:cc:dd:ee:ff)" = '手机 100% "别名"' ] || exit 1
[ "$(getname 192.0.2.1 11:22:33:44:55:66)" = 'IP fallback' ] || exit 1
echo 'PASS: exact MAC/IP alias matching and literal percent/quotes'
