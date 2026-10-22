#!/bin/bash
# Run on the target's Bash/libc too: glibc and musl printf differ on raw UTF-8 bytes.
source_file="${1:-root/usr/share/wechatpush/wechatpush}"
testdir=$(mktemp -d) || exit 1
trap 'rm -f "$testdir/functions.sh"; rmdir "$testdir"' EXIT
sed -n '/^utf8_byte_value() {/,/^}/p; /^length_str() {/,/^}/p; /^cut_str() {/,/^}/p; /^pad_field() {/,/^}/p' "$source_file" > "$testdir/functions.sh"
. "$testdir/functions.sh"
check() { [ "$1" = "$2" ] || { printf 'FAIL: expected <%s>, got <%s>\n' "$2" "$1"; exit 1; }; }
for locale in C C.UTF-8 en_US.UTF-8; do
    export LC_ALL="$locale"
    for iteration in {1..20}; do
        check "$(utf8_byte_value $'\xe4')" 228
        check "$(utf8_byte_value $'\x80')" 128
        check "$(length_str '主卧窗帘')" 8
        check "$(length_str '↙ 5.83 M')" 8
        check "$(length_str 'A😀中')" 5
        check "$(cut_str '主卧窗帘' 16)" '主卧窗帘'
        check "$(cut_str '主卧窗帘很长很长很长测试' 16)" '主卧窗帘很长很长..'
        check "$(cut_str 'A😀中' 3)" 'A😀..'
        check "$(cut_str '↙ 5.83 M' 16)" '↙ 5.83 M'
    done
done
printf 'PASS: UTF-8 Chinese, arrows, emoji and boundaries across 3 locales, 20 rounds each\n'
