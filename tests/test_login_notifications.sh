#!/bin/bash
source_file="${1:-root/usr/share/wechatpush/wechatpush}"
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
sed -n '/^login_notice_due() {/,/^}/p; /^login_notice_record() {/,/^}/p; /^login_send() {/,/^}/p' "$source_file" > "$dir/functions"
. "$dir/functions"
translate() { local fmt="$1"; shift; printf "$fmt" "$@"; }
log_change() { [ "${debuglevel:-1}" = 1 ] && printf '%s\n' "$*" >> "$dir/log"; return 0; }
get_ip_attribution() { :; }
logread() { :; }
field_spaces() { :; }
disturb() { return "${global_disturb:-0}"; }
date() { printf '%s\n' "$clock"; }
diy_send() { printf 'attempt\n' >> "$dir/sends"; return "${send_failure:-0}"; }
count() { if [ -f "$1" ]; then wc -l < "$1"; else printf 0; fi; }
check() { [ "$1" = "$2" ] || { printf 'FAIL %s != %s\n' "$1" "$2"; exit 1; }; }
login_disturb=2; login_notification_delay=600; login_log_enable=1
clock=1000; login_send 192.0.2.1 10:00 web_login_counts
check "$(count "$dir/sends")" 1
clock=1050; login_send 192.0.2.1 10:01 ssh_login_counts
clock=1599; login_send 192.0.2.1 10:09 web_login_counts
check "$(count "$dir/sends")" 1; check "$(count "$dir/log")" 1
clock=1600; login_send 192.0.2.1 10:10 ssh_login_counts
check "$(count "$dir/sends")" 2
login_log_enable=0; clock=1601; login_send 192.0.2.1 10:10 web_login_counts
check "$(count "$dir/sends")" 2; check "$(count "$dir/log")" 3
# Clearing/disabling the public log must not reset or suppress the notification window.
rm -f "$dir/log"; debuglevel=0; clock=1602
login_send 192.0.2.1 10:10 web_login_counts
check "$(count "$dir/sends")" 2
clock=2200; login_send 192.0.2.1 10:20 web_login_counts
check "$(count "$dir/sends")" 3
# Different IPs have independent windows; Web/SSH and failure events from the same IP share the original suppression rule.
login_send 192.0.2.2 10:20 web_login_counts
login_send 192.0.2.1 10:20 web_failed_counts
check "$(count "$dir/sends")" 4
# Failed delivery or global do-not-disturb must not start a successful-send window.
send_failure=1; login_send 192.0.2.3 10:20 ssh_login_counts
send_failure=0; login_send 192.0.2.3 10:20 ssh_login_counts
check "$(count "$dir/sends")" 6
global_disturb=1; login_send 192.0.2.4 10:20 web_login_counts
global_disturb=0; login_send 192.0.2.4 10:20 web_login_counts
check "$(count "$dir/sends")" 7
# Whitelist affects automatic blocking, not the notification mode.
for login_disturb in '' 1 2; do
 for login_log_enable in 0 1; do
  for listed in 0 1; do
   rm -f "$dir/sends" "$dir/log" "$dir/login_notice_times.json"
   debuglevel=1; login_ip_white_list=''; [ "$listed" = 1 ] && login_ip_white_list='192.0.2.5'
   clock=3000; login_send 192.0.2.5 11:00 web_login_counts
   first=$(count "$dir/sends")
   clock=3599; login_send 192.0.2.5 11:09 ssh_login_counts
   repeat=$(count "$dir/sends")
   clock=3600; login_send 192.0.2.5 11:10 web_login_counts
   case "$login_disturb" in
    1) check "$first" 0; check "$repeat" 0; check "$(count "$dir/sends")" 0
       check "$(count "$dir/log")" 3 ;;
    2) check "$first" 1; check "$repeat" 1; check "$(count "$dir/sends")" 2
       if [ "$login_log_enable" = 1 ]; then check "$(count "$dir/log")" 2; else check "$(count "$dir/log")" 3; fi ;;
    *) check "$first" 1; check "$repeat" 2; check "$(count "$dir/sends")" 3; check "$(count "$dir/log")" 3 ;;
   esac
  done
 done
done
[ ! -e "$dir/send_enable.lock" ] || exit 1
echo 'PASS: 12 mode/whitelist/anti-flood combinations, first/599/600 seconds, logs independent, failed sends and global DND'
