#!/bin/bash
source_file="${1:-root/usr/share/wechatpush/wechatpush}"
dir=$(mktemp -d) || exit 1
trap 'rm -f "$dir/functions" "$dir/aliases" "$dir/host_hints.json" "$dir/devices.json" "$dir/send_pid"; rmdir "$dir"' EXIT
sed -n '/^getname() {/,/^}/p; /^process_and_check() {/,/^}/p' "$source_file" > "$dir/functions"
. "$dir/functions"
cut_str() { printf '%s\n' "$1"; }
uci() { :; }
device_aliases_path="$dir/aliases"; devices_json="$dir/devices.json"
: > "$device_aliases_path"; : > "$dir/send_pid"
echo '{"devices":[{"ip":"192.0.2.1","mac":"aa:bb:cc:dd:ee:ff","name":"unknown"}]}' > "$devices_json"
echo '{"AA-BB-CC-DD-EE-FF":{"name":"iQOO-15.lan"}}' > "$dir/host_hints.json"
[ "$(getname 192.0.2.1 aa:bb:cc:dd:ee:ff)" = 'iQOO-15' ] || exit 1
echo 'aa:bb:cc:dd:ee:ff My alias.lan' > "$device_aliases_path"
[ "$(getname 192.0.2.1 aa:bb:cc:dd:ee:ff)" = 'My alias.lan' ] || exit 1
: > "$device_aliases_path"
echo '{"AA-BB-CC-DD-EE-FF":{"name":"anonymous"}}' > "$dir/host_hints.json"
[ "$(getname 192.0.2.1 aa:bb:cc:dd:ee:ff)" = 'unknown' ] || exit 1
echo 'PASS: shared host hints recover unknown names by MAC; aliases retain priority and placeholders remain internal'
