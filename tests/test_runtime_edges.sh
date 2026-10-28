#!/bin/bash
set -e
source_file="${1:-root/usr/share/wechatpush/wechatpush}"
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
sed -n '/^get_config() {/,/^}/p; /^read_config() {/,/^}/p; /^read_json() {/,/^}/p; /^wait_and_cat() {/,/^}/p; /^in_disturb_window() {/,/^}/p; /^disturb() {/,/^}/p; /^finish_send() {/,/^}/p; /^send() {/,/^}/p; /^get_client_usage() {/,/^}/p' "$source_file" > "$dir/functions"
. "$dir/functions"
export LC_ALL=C
uci() { printf '%s' "用户's 密码\$(touch SHOULD_NOT_EXIST)"; }
get_config fixture
[ "$fixture" = "用户's 密码\$(touch SHOULD_NOT_EXIST)" ]
[ ! -e SHOULD_NOT_EXIST ]
output_dir="$dir/input"; mkdir "$output_dir"
printf '%s' "Tom's 中文↑↓" > "$output_dir/literal"
wait_and_cat
[ "$literal" = "Tom's 中文↑↓" ]
for window in '23 8' '8 23' '0 8' '8 8'; do
 read -r start end <<< "$window"
 for hour in {0..23}; do
  expected=1
  if (( start < end )); then (( hour >= start && hour < end )) && expected=0
  else (( hour >= start || hour < end )) && expected=0; fi
  actual=0; in_disturb_window "$hour" "$start" "$end" || actual=$?
  [ "$actual" = "$expected" ]
 done
done
printf 23 > "$dir/hour"
date() { [ "$1" = +%H ] && cat "$dir/hour" || printf 220; }
sleep() { printf 8 > "$dir/hour"; printf slept > "$dir/slept"; }
enable_detection() { :; }
log_change() { :; }
translate() { printf "$1" "${@:2}"; }
do_not_disturb_mode=1; do_not_disturb_starttime=23; do_not_disturb_endtime=8; sleeptime=1
disturb
[ -f "$dir/slept" ]
unset do_not_disturb_mode do_not_disturb_starttime do_not_disturb_endtime

# Scheduled/test sends must retain pending daemon events and shared output.
get_config() { :; }
disturb() { return "${fixture_dnd:-0}"; }
jsonpath=fixture; send_title='发送测试'; str_splitline=''; str_title_start=''; str_title_end=''; str_linefeed=''; str_tab=''
diy_send() { [ -n "$2" ]; }
printf pending > "$dir/device_events"; printf daemon > "$dir/input/current_device"
send test
[ "$(cat "$dir/device_events")" = pending ]
[ "$(cat "$dir/input/current_device")" = daemon ]
[ ! -e "$dir/send_pid" ] && [ ! -e "$dir/send_enable.lock" ]
fixture_dnd=1
if ! send test; then echo 'FAIL: skipped DND send returned failure'; exit 1; fi
unset fixture_dnd
[ ! -e "$dir/send_pid" ]
exec 9>"$dir/scheduled_send.lock"; flock 9
if send test; then echo 'FAIL: overlapping scheduled send accepted'; exit 1; fi
exec 9>&-
cron() { touch "$dir/cron-called"; }
deltemp() { rm -f "$dir/device_events"; }
jsonpath=''
if ! read_config test; then echo 'FAIL: one-shot configuration failed'; exit 1; fi
[ ! -e "$dir/cron-called" ]
[ "$(cat "$dir/device_events")" = pending ]
[ "$(cat "$dir/input/current_device")" = daemon ]

# 1000 bytes over 120 seconds is 500 bytes/minute, not 1000.
devices_json="$dir/devices.json"
printf '%s' '{"devices":[{"name":"Phone","mac":"aa:bb:cc:dd:ee:ff","ip":"192.0.2.1","status":"online","uptime":"1"}]}' > "$devices_json"
get_qwrt_usage_stats() { printf '1100 650 450 1'; }
getname() { printf Phone; }
bytes_for_humans() { printf '%s' "$1"; }
time_for_humans() { printf '%s' "$1"; }
field_spaces() { :; }
get_signal_dbm() { return 1; }
qwrt_traffic_enable=1; client_usage=1; client_usage_max=800; client_usage_disturb=0
get_client_usage_time=100; title=''; content=''; name='WrongDevice'
printf 'aa:bb:cc:dd:ee:ff 100 50 50 1\n' > "$dir/old_client_usage_aliases"
get_client_usage
[ -z "$title" ]
client_usage_max=400; get_client_usage_time=100
printf 'aa:bb:cc:dd:ee:ff 100 50 50 1\n' > "$dir/old_client_usage_aliases"
get_client_usage
[ "$title" = 'Phone abnormal traffic' ]
echo 'PASS: literal UCI/output, 96 hour boundaries, midnight pause, isolated/serialized sends, per-minute traffic and correct alert name'
