#!/bin/bash
source_file="${1:-root/usr/share/wechatpush/wechatpush}"
testdir=$(mktemp -d) || exit 1
trap 'rm -f "$testdir/functions" "$testdir/input" "$testdir/output"; rmdir "$testdir"' EXIT
sed -n '/^initialize_utf8_runtime() {/,/^}/p; /^get_config() {/,/^}/p' "$source_file" > "$testdir/functions"
. "$testdir/functions"
uci() { printf auto; }
for caller_locale in C C.UTF-8 en_US.UTF-8; do
    export LANG="$caller_locale" LC_ALL="$caller_locale"
    unset wechatpush_requested_locale
    if [ "${2:-}" != baseline ]; then
        initialize_utf8_runtime
        [ "$LC_ALL" = C ] && [ "$wechatpush_requested_locale" = "$caller_locale" ] || exit 1
        get_config lang
        case "$caller_locale" in en_US.UTF-8) [ "$lang" = en_us ] || exit 1 ;; *) [ "$lang" = c ] || exit 1 ;; esac
    fi
    for padding in 509 510 511 1021 1022 1023 1533 1534 1535; do
        printf -v prefix '%*s' "$padding" ''
        for text in '时↓主卧窗帘9小时41分↑123.23 K/↓93.55 K' '😀中文↑下载↓'; do
            printf '%s%s' "$prefix" "$text" > "$testdir/input"
            for iteration in 1 2 3; do
                value=$(cat "$testdir/input")
                printf '%s' "$value" > "$testdir/output"
                if ! cmp -s "$testdir/input" "$testdir/output"; then
                    printf 'FAIL: command substitution corrupted UTF-8 locale=%s padding=%s\n' "$caller_locale" "$padding"
                    exit 1
                fi
            done
        done
    done
done
if [ "${2:-}" != baseline ]; then
    export LANG=zh_CN.UTF-8
    unset wechatpush_requested_locale
    initialize_utf8_runtime
    get_config lang
    [ "$lang" = zh_cn ] || exit 1
fi
echo 'PASS: 162 UTF-8 command substitutions around 512-byte boundaries; original auto-language retained'
