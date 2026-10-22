#!/bin/bash
source_file="${1:-root/usr/share/wechatpush/wechatpush}"
testdir=$(mktemp -d) || exit 1
trap 'rm -f "$testdir/functions.sh" "$testdir/devices.json" "$testdir/devices.tmp"; rmdir "$testdir"' EXIT
sed -n '/^tplink_hold_offline() {/,/^}/p; /^down() {/,/^}/p' "$source_file" > "$testdir/functions.sh"
. "$testdir/functions.sh"
dir="$testdir"; devices_json="$dir/devices.json"; tmp_devices_json="$dir/devices.tmp"
silent_run() { :; }
getmac() { printf '%s' "$fixture_mac"; }
getping() { observed="$3/$4"; return 1; }
blackwhitelist() { return "$fixture_filter"; }
getname() { echo fixture; }
getinterface() { echo br-lan; }
tplink_enable=0; down_timeout=120; timeout_retry_count=5
count=0
for qwrt_online_enable in 0 1; do
 for only_timeout_push in 0 1; do
  for mac_filtering_mode_1 in offline_custom close; do
   for fixture_filter in 0 1; do
    for listed in 0 1; do
     fixture_mac='aa:bb:cc:dd:ee:ff'
     offline_detection_mac_list='11:22:33:44:55:66'
     [ "$listed" = 1 ] && offline_detection_mac_list="$fixture_mac"
     echo '{"devices":[{"ip":"192.0.2.1","status":"online"}]}' > "$devices_json"
     observed=''
     down 192.0.2.1
     expected='120/5'
     if [ "$only_timeout_push" = 1 ]; then
      if [ "$mac_filtering_mode_1" = offline_custom ]; then
       [ "$listed" = 1 ] || expected='10/2'
      else
       [ "$fixture_filter" = 0 ] || expected='10/2'
      fi
     fi
     [ "$observed" = "$expected" ] || { echo "FAIL: native=$qwrt_online_enable checked=$only_timeout_push mode=$mac_filtering_mode_1 filter=$fixture_filter listed=$listed expected=$expected got=$observed"; exit 1; }
     count=$((count+1))
    done
   done
  done
 done
done
echo "PASS: $count timeout-selector combinations; unchecked always uses custom parameters"
