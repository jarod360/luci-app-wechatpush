# Introduction

[![Lastest Release](https://img.shields.io/github/release/tty228/luci-app-wechatpush.svg?style=flat)](https://github.com/tty228/luci-app-wechatpush/releases)
[![GitHub All Releases](https://img.shields.io/github/downloads/tty228/luci-app-wechatpush/total)](https://github.com/tty228/luci-app-wechatpush/releases)

[中文文档](README.md) | [English](README_en.md)

**OpenWrt Notification Plugin – Send Alerts to WeChat or Telegram**

This OpenWrt plugin delivers real-time router notifications to your mobile device via **WeChat** or **Telegram** or **Mail**. Monitor your network with alerts for:

- [x] IP changes (IPv4/IPv6)
- [x] Device connections (online/offline)
- [x] Online client list & traffic usage
- [x] CPU load & temperature (including virtualized hosts like PVE)
- [x] Router status reports
- [x] Security alerts (failed web/SSH logins with auto blacklist)
- [x] Port knocking & automated tasks

Auto-banning blocks blacklisted IPs from accessing the router. Optionally block all forwarded traffic from blacklisted IPs, including access to port-forwarded downstream devices and Internet access by LAN clients. With forwarded-traffic blocking enabled and conntrack installed, banning also attempts to clear that IP's existing connection-tracking entries to interrupt offloaded flows; without conntrack, this step is skipped while new connections remain blocked by the blacklist rules. Turning the option off, or turning auto-ban off, removes the forwarded-traffic drop rules on the next detection cycle; like the router-access drop rules, they are not removed by stopping the service, disappear after a firewall reload or reboot, and are restored on the plugin's next detection cycle while it runs. fw4 timed bans are restored with their last recorded remaining duration. Set the blacklist duration to `0` for permanent bans; remove the IP from the blacklist to lift the ban.

Supported services:
| Push application | Method | description |
| :-------- | :----- | :----- |
| WeChat | Server Chan | https://sct.ftqq.com/
| WeChat | PushPlus | http://www.pushplus.plus/
| WeChat etc. | WPUSH | https://wpush.cn/
| WeChat | WxPusher | https://wxpusher.zjiecode.com/docs
| WeChat for Enterprise | Application Push | https://work.weixin.qq.com/api/doc/90000/90135/90248
| Telegram | bot | https://t.me/BotFather
| Mail | msmtp | https://marlam.de/msmtp/

Limited resources are available. If you need services such as DingTalk push, Feishu push, Bark push, etc., please try another branch at https://github.com/zzsj0928/luci-app-pushbot, or use **custom API settings**.

## Instructions

**Regarding Installation:**

The plugin requires dependencies on iputils-arping + curl + jq + bash. For routers with limited memory, please consider the installation carefully. **Before installing, please run the opkg update command to install dependencies during the installation process.**

Developed based on X86 OpenWrt v23.05.0, different systems and devices may encounter various issues. **If you encounter errors in temperature information retrieval, display errors, or other issues, please adapt accordingly.**

**Regarding Hostnames:**

For devices that do not declare hostnames, devices connected via optical modem dial-up, OpenWrt used as a bypass gateway, and other scenarios where hostname retrieval fails, you can set the hostname using the following methods:

- Use device name remarks.
- Configure to obtain the hostname from the optical modem in advanced settings.
- Enable MAC device database.
- Install samba*-server or samba*-client to enable the program to query hostnames via NetBIOS.


**Regarding Device Online Status:**

“QWRT native online detection” is disabled by default. When disabled, the plugin retains its original active-detection flow: it checks the wireless station state, then uses the existing ARP information to choose `arping` or `ping`, applying the configured detection parameters. Enable this option only when using QWRT 2026.10.6 or later.

When enabled, online status is determined using the same ARP/MAC rules as the QWRT LuCI overview. The plugin reads `/usr/libexec/luci-arp` (which outputs `/proc/net/arp` by default on QWRT), counts only valid unicast MAC records with valid IPv4 addresses on `br-lan` whose ARP flags include `0x2`, and determines device status by MAC address. It does not send ping/arping probes. Device status is polled every 5 seconds by default; if `sleeptime` is configured below 5 seconds, that shorter interval is used. Routine tasks such as network checks and traffic alerts continue to follow `sleeptime`. Because this method depends on the current ARP table, sleeping devices or devices without a valid ARP entry may be reported offline.

**Offline timeout and detection count:** The “Device offline detection timeout” and “Offline detection count” settings in Advanced determine the offline confirmation conditions together. With QWRT native detection, the first failed check counts as failure number 1. A device is marked offline only after both the configured timeout has elapsed and the configured total number of failed checks has been reached. The count is the total number of failed checks, not the number of additional retries after the first failure. If the count is reached before the timeout, the plugin waits for the timeout condition rather than performing an extra probe. If a later poll finds the device online again before offline confirmation, its status returns to online and the pending failure counters are cleared; no offline event is generated for that pending outage. For example, with a timeout of 15 seconds and a count of 3, the first failure is count 1; offline is confirmed only after at least 15 seconds and 3 failed checks. Actual check times may vary slightly with the 5-second polling interval.

**MAC-based custom offline detection:** An “Offline custom detection list” is added in the “MAC Filtering Mode 1” area. It is not an independent enable switch and does not change the original push filter:
- When the original “Offline timeout applies only to the devices that receive push notifications” option is active under its existing logic, the plugin first evaluates the original online/offline push filter.
- Devices that pass the original filter continue to use the configured custom timeout and detection count; the new list does not change that result.
- For devices excluded by the original filter, only MAC addresses in the new list are restored to the configured custom timeout and count. Devices outside the list, or devices whose MAC address is unavailable, retain the original defaults of 10 seconds and 2 checks.
- An empty list leaves the original behavior unchanged. If the original prerequisite option is not active, the new list is ignored and all devices continue to use the configured custom parameters.
- The list changes offline detection parameters only; it does not change notification switches, MAC filtering, or actual push eligibility.

- If devices frequently sleep, adjust the offline timeout and detection count according to the device behavior.
- If precise online status is not required, you can disable active detection in Advanced settings.
- QWRT native online detection is disabled by default; do not enable it on non-QWRT systems.

**Regarding Traffic Statistics:**

Traffic statistics functionality depends on `wrtbwmon`. Please install or compile it yourself. **Enabling this plugin will conflict with Routing/NAT, Flow Offloading, proxy internet access, and other plugins, resulting in the inability to obtain traffic statistics. Please choose accordingly.**

**About Hard Drive Information:**

When the OpenWrt system or remote host (PVE) does not have lsblk installed, the hard drive capacity information may be inconsistent with the actual capacity.

When the OpenWrt system or remote host (PVE) does not have smartctl installed, information such as hard drive temperature, uptime, and health status will not be available.

**Regarding Bug Submissions:**

When submitting a bug, please provide the following information if possible:

- Device information and plugin version number.
- Prompt information after executing `/usr/share/wechatpush/wechatpush`.
- Log information and file information in the `/tmp/wechatpush/` directory after encountering an error.
- Detailed execution information of `bash -x /usr/share/wechatpush/wechatpush t1`.

## DownLoad

| Supported OpenWrt Versions | Download Link |
| :-------- | :----- |
| openwrt-19.07.0 ... latest | [![Lastest Release](https://img.shields.io/github/release/tty228/luci-app-wechatpush.svg?style=flat)](https://github.com/tty228/luci-app-wechatpush/releases)
| openwrt-18.06 | [![Release v2.06.2](https://img.shields.io/badge/release-v2.06.2-lightgrey.svg)](https://github.com/tty228/luci-app-wechatpush/releases/tag/v2.06.2)

## Donate

If you feel that this project is helpful to you, please donate to us so that the project can continue to develop and be more perfect.

![image](https://github.com/tty228/luci-app-wechatpush/blob/master/.github/others/20260303202537_34_664.png)