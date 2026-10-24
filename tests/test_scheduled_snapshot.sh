#!/bin/bash
source_file="${1:-root/usr/share/wechatpush/wechatpush}"
api_dir="${2:-root/usr/share/wechatpush/api}"
dir=$(mktemp -d) || exit 1
trap 'rm -rf "$dir"' EXIT
sed -n '/^initialize_utf8_runtime() {/,/^}/p; /^wait_and_cat() {/,/^}/p; /^diy_send() {/,/^}/p' "$source_file" > "$dir/functions"
. "$dir/functions"
initialize_utf8_runtime
translate() { printf '%s' "$1"; }
log_change() { :; }
qywx_get_token() { printf fixture-token; }
qywx_upload_media() { printf fixture-media; }
run_with_tag() { [ "$1" = curl ] || return 99; printf '{"errcode":0}'; }
output_dir="$dir/output"; mkdir "$output_dir"; : > "$dir/send_pid"
expected="<table border='0'><tr><td>Tom's 索尼音响</td><td>9小时41分</td><td>↑9.69 M/↓10.77 M</td></tr></table>"
printf '%s' "$expected" > "$output_dir/current_device"
wait_and_cat
[ "$current_device" = "$expected" ] || { echo 'FAIL: scheduled input was reparsed as shell code'; exit 1; }
push_kind=scheduled; userid=fixture; agentid=1; lite_enable=nowtime
qywx_api_url='https://example.invalid'; jsonpath="$api_dir/qywx_mpnews.json"
diy_send '定时推送' "$current_device" "$jsonpath" || exit 1
[ "$(cat "$dir/scheduled_diagnostics/body.html")" = "$expected" ] || exit 1
[ "$(cat "$dir/scheduled_diagnostics/client_list.raw")" = "$expected" ] || exit 1
[ "$(jq -r '.mpnews.articles[0].content' "$dir/scheduled_diagnostics/payload.json")" = "$expected" ] || exit 1
if grep -Rq 'fixture-token\|example.invalid' "$dir/scheduled_diagnostics"; then exit 1; fi
rm "$output_dir/current_device"
diy_send '定时推送' "$expected" "$jsonpath" || exit 1
[ ! -e "$dir/scheduled_diagnostics/client_list.raw" ] || { echo 'FAIL: stale scheduled raw list retained'; exit 1; }
[ "$(cat "$dir/scheduled_diagnostics/body.html")" = "$expected" ] || exit 1
echo 'PASS: scheduled raw list/body/JSON round-trip literal quotes and Unicode; diagnostics contain no URL/token; no network send'
