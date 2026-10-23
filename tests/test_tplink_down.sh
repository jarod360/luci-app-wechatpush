#!/bin/bash
# Deterministic fixtures; never source or modify the installed daemon/configuration.
source_file="${1:-root/usr/share/wechatpush/wechatpush}"
testdir=$(mktemp -d) || exit 1
trap 'rm -f "$testdir/devices.json" "$testdir/devices.tmp" "$testdir/functions.sh"; rmdir "$testdir"' EXIT
sed -n '/^tplink_hold_offline() {/,/^}/p; /^down() {/,/^}/p' "$source_file" > "$testdir/functions.sh"
. "$testdir/functions.sh"
set -- "$testdir"
lua() { :; }
refresh_tplink_fallback() { :; }

dir="$1"
devices_json="$dir/devices.json"
tmp_devices_json="$dir/devices.tmp"
getmac() { echo 'aa:bb:cc:dd:ee:ff'; }
getping() { return "$test_native"; }
getname() { echo 'fixture'; }
getinterface() { echo 'br-lan'; }
silent_run() { :; }
tplink_mac_state() { printf '%s' "$test_tplink"; }
down_timeout=0
timeout_retry_count=1
reset_device() { echo '{"devices":[{"ip":"192.0.2.1","mac":"aa:bb:cc:dd:ee:ff","name":"fixture","interface":"br-lan","status":"online"}]}' > "$devices_json"; }
expect_state() { actual=$(jq -r '.devices[0].status' "$devices_json"); [ "$actual" = "$1" ] || { echo "FAIL $case expected=$1 actual=$actual"; exit 1; }; }
for qwrt_online_enable in 0 1; do
  for tplink_enable in 0 1; do
    for test_native in 0 1; do
      for test_tplink in online offline unknown '' unmanaged pending; do
        case="$qwrt_online_enable/$tplink_enable/$test_native/$test_tplink"
        reset_device
        down 192.0.2.1
        down 192.0.2.1
        expected=online
        if { [ "$tplink_enable" = 1 ] && [ "$test_tplink" = offline ]; } || { [ "$test_native" = 1 ] && { [ "$tplink_enable" = 0 ] || [ "$test_tplink" = unmanaged ]; }; }; then expected=offline; fi
        expect_state "$expected"
      done
    done
  done
done
echo 'PASS: 48 native/legacy/auxiliary state combinations'
reset_device
tplink_enable=1; test_tplink=online
jq '.devices[0].name="unknown"' "$devices_json" > "$tmp_devices_json" && mv "$tmp_devices_json" "$devices_json"
down 192.0.2.1
[ "$(jq -r '.devices[0].name' "$devices_json")" = fixture ] || exit 1
expect_state online
echo 'PASS: auxiliary online branch refreshes device names without changing presence'
# Returning TP-LINK presence must clear prior QWRT debounce markers.
qwrt_online_enable=1; tplink_enable=1; test_native=1; test_tplink=online
echo '{"devices":[{"ip":"192.0.2.1","status":"unknown","qwrt_offline_since":1,"qwrt_offline_retries":3}]}' > "$devices_json"
down 192.0.2.1
expect_state online
jq -e '.devices[0] | has("qwrt_offline_since") | not' "$devices_json" >/dev/null || exit 1
echo 'PASS: auxiliary presence clears pending offline counters'

# An already-offline wireless client recovered before notification preparation.
sed -n '/^down_send() {/,/^}/p' "$source_file" >> "$testdir/functions.sh"
. "$testdir/functions.sh"
blackwhitelist() { return 0; }
clear_offline_devices() { :; }
current_device() { echo 'FAIL: unexpected offline notification'; exit 1; }
tplink_enable=1; test_tplink=online; notification_offline=1
reset_device
jq '.devices[0].status="offline"' "$devices_json" > "$tmp_devices_json" && mv "$tmp_devices_json" "$devices_json"
content=''
down_send
expect_state online
[ "$offline_push_pending" = 0 ] && [ -z "$content" ] || exit 1
echo 'PASS: recovered wireless client is cancelled before notification content'

# Local ARP/active probes cannot resurrect an offline TP-LINK client in up().
sed -n '/^up() {/,/^}/p' "$source_file" >> "$testdir/functions.sh"
. "$testdir/functions.sh"
getping() { echo 'FAIL: local probe used for TP-LINK offline/pending' >&2; exit 1; }
for test_tplink in offline pending; do
    reset_device
    jq '.devices[0].status="offline"' "$devices_json" > "$tmp_devices_json" && mv "$tmp_devices_json" "$devices_json"
    up 192.0.2.1
    expect_state offline
done
echo 'PASS: stale local presence cannot undo a TP-LINK offline decision'
