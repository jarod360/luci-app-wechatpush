#!/bin/bash
# Render only: all messaging/network functions are stubbed. Never sends a message.
source_file="${1:-root/usr/share/wechatpush/wechatpush}"
api_dir="${2:-root/usr/share/wechatpush/api}"
dir=$(mktemp -d) || exit 1
trap 'rm -f "$dir/functions.sh" "$dir/payload.json"; rmdir "$dir"' EXIT
sed -n '/^utf8_byte_value() {/,/^}/p; /^length_str() {/,/^}/p; /^cut_str() {/,/^}/p; /^diy_send() {/,/^}/p' "$source_file" > "$dir/functions.sh"
. "$dir/functions.sh"
translate() { printf '%s' "$1"; }
log_change() { :; }
qywx_get_token() { printf 'fixture-token'; }
qywx_upload_media() { printf 'fixture-media'; }
run_with_tag() { [ "$1" = curl ] || return 99; cp "$tempjsonpath" "$fixture_payload"; printf '{"errcode":0}'; }
tempjsonpath="$dir/shared.json"
fixture_payload="$dir/payload.json"
userid=fixture
agentid=1
lite_enable=nowtime
str_linefeed='\n'
qywx_api_url='https://example.invalid'
body="主卧窗帘 ↙ 5.83 M ↓ 5.83 MB $(cut_str '主卧窗帘很长很长很长测试' 16)"
for mode in qywx_markdown qywx_mpnews; do
    jsonpath="$api_dir/$mode.json"
    diy_send '中文模板测试' "$body" "$jsonpath" || exit 1
    rendered=$(jq -r '.text.content // .mpnews.articles[0].content' "$fixture_payload") || exit 1
    [[ "$rendered" == *"$body"* ]] || { echo 'FAIL: template changed UTF-8 content'; exit 1; }
    [[ "$rendered" != *'�'* ]] || { echo 'FAIL: UTF-8 replacement character'; exit 1; }
done
echo 'PASS: text and mpnews JSON templates preserve Chinese, arrows and trimmed names; no network messages sent'
