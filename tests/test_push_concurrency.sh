#!/bin/bash
# Render concurrently with mocked network calls. Never sends a notification.
source_file="${1:-root/usr/share/wechatpush/wechatpush}"
api_dir="${2:-root/usr/share/wechatpush/api}"
dir=$(mktemp -d) || exit 1
trap 'rm -f "$dir"/functions.sh "$dir"/captured.*.json "$dir"/shared.json "$dir"/push.*; rmdir "$dir"' EXIT
sed -n '/^diy_send() {/,/^}/p' "$source_file" > "$dir/functions.sh"
. "$dir/functions.sh"
translate() { printf '%s' "$1"; }
log_change() { printf '%s\n' "$*" >&2; }
qywx_get_token() { printf fixture-token; }
qywx_upload_media() { printf fixture-media; }
run_with_tag() {
 [ "$1" = curl ] || return 99
 local request_payload=''
 while [ "$#" -gt 0 ]; do
  if [ "$1" = -d ]; then request_payload="${2#@}"; break; fi
  shift
 done
 [ "$request_payload" = "$tempjsonpath" ] || return 40
 # Model another scanner cleaning the old globally shared request file.
 rm -f "$dir/shared.json"
 sleep 1
 local rendered
 rendered=$(jq -r '.text.content // .mpnews.articles[0].content' "$request_payload") || return 41
 [[ "$rendered" == *"$fixture_body"* ]] || return 42
 [ -z "$(LC_ALL=C tr -d '\000-\177' < "$request_payload")" ] || return 43
 cp "$request_payload" "$dir/captured.$fixture_id.json" || return 44
 printf '{"errcode":0}'
}
userid=fixture; agentid=1; lite_enable=nowtime; str_linefeed='\n'; qywx_api_url=https://example.invalid
tempjsonpath="$dir/shared.json"
pad=$(printf '%025000d' 0)
pids=()
for fixture_id in {1..12}; do
 (
  fixture_body="并发设备$fixture_id 主卧窗帘 ↩ 2.30 M ↙ 5.83 M ↑ ↓ 😀 $pad"
  if [ "$((fixture_id % 2))" = 0 ]; then jsonpath="$api_dir/qywx_mpnews.json"; else jsonpath="$api_dir/qywx_markdown.json"; fi
  diy_send "fixture-$fixture_id" "$fixture_body" "$jsonpath"
 ) &
 pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid" || { echo 'FAIL: concurrent payload corrupted/deleted'; exit 1; }; done
[ "$(find "$dir" -name 'captured.*.json' | wc -l)" = 12 ] || exit 1
[ -z "$(find "$dir" -name 'push.*')" ] || { echo 'FAIL: temporary payload leaked'; exit 1; }
echo 'PASS: 12 concurrent 25KB Unicode payloads survive shared-file cleanup and remain ASCII JSON'

