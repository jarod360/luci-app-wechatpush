# luci-app-wechatpush

[![Build](https://github.com/jarod360/luci-app-wechatpush/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/jarod360/luci-app-wechatpush/actions/workflows/build.yml)
![Version](https://img.shields.io/badge/version-3.6.20-blue)
[![License](https://img.shields.io/badge/license-GPL--2.0-blue.svg)](LICENSE)

[简体中文](README.md) | [English](README_en.md)

## Overview

**luci-app-wechatpush** is an OpenWrt LuCI plugin for network monitoring and notifications. This repository is a maintained fork of [tty228/luci-app-wechatpush](https://github.com/tty228/luci-app-wechatpush). It retains the upstream notification and monitoring functions while adding QWRT-native traffic and online detection, IP geolocation lookup, batched device-event notifications, and compatibility fixes.

Current package version: **3.6.20-3**

## Features

- **Network notifications**: Detect IPv4/IPv6 address changes and report network status.
- **Client monitoring**: Track LAN device online/offline status and display connected clients; supports device aliases and MAC vendor information.
- **Batched device events**: Combine device state changes found during one detection cycle into a single notification.
- **System and host monitoring**: Monitor router CPU, temperature, and runtime status; retrieve temperature and disk information from remote hosts such as PVE over SSH.
- **Security notifications and protection**: Web/SSH login alerts, automatic banning after failed logins, optional blocking of forwarded traffic from blacklisted IPs, and port knocking.
- **Unattended tasks**: Run configured automation based on device presence, Do-Not-Disturb periods, and other conditions.
- **Notification providers**: Server Chan, Server Chan 3, PushPlus, WPUSH, WxPusher, WeCom, Telegram Bot, msmtp email, and custom API templates.

## Main fork-specific extensions

The following summarizes the major additions and maintenance changes compared with the upstream repository. Exact behavior is defined by the current source code.

### IP geolocation extension

- Look up locations for login alerts.
- IPv4 can use a configured local ip2region XDB database first, with online lookup as fallback.
- Results are normalized without continent, district/county, ISP, or ASN details.

### WeCom API Base URL

- Configure a custom WeCom API Base URL; when empty, the official API endpoint is used.

### QWRT-native features

**Native QWRT traffic statistics are an extension added by this fork.** This repository has removed the original third-party-plugin-based traffic monitoring to avoid compatibility conflicts with proxy-routing plugins. Current traffic features use only the new QWRT-native integration: cumulative traffic, device traffic display and per-minute traffic-increment alerts. Systems without compatible QWRT support have no fallback to the removed legacy traffic plugin.

These options require **QWRT 2026.10.6 or later** and are enabled separately under Basic Settings:

- **QWRT native traffic statistics**: Reads cumulative traffic through `luci.client-rates get`. The data is used for online-device information, device notifications, abnormal-traffic alerts, and unattended low-traffic checks. This implementation no longer depends on or calls the legacy `wrtbwmon`.
- **QWRT native online detection**: Determines client state using the ARP/MAC rules used by the QWRT LuCI overview. It does not send active ping/arping probes. Because it relies on the current ARP table, sleeping clients or clients without a valid ARP entry may be reported offline.

Both QWRT options are independent and disabled by default. Do not enable them on non-QWRT systems.

### TP-LINK wireless presence assistance (3.6.20)

**Added by this fork:** optional TP-LINK AC router integration provides a 30-second wireless disconnect check to reduce roaming false alarms and detector delays, with an online-client dialog.

Disabled by default. Under Basic Settings, below QWRT native online detection, enable TP-LINK assistance, enter its management IPv4 address, username and password, then choose **Save & Apply**. No Home Assistant, SSH, diagnostic mode or TP-LINK configuration changes are required.

- The green wireless online count opens a client list with name, IP, MAC, AP and SSID. Screens up to 767 px show name, IP and AP only. Saved WeChatPush aliases take precedence (MAC, then IP), then QWRT host hints and the main local client table, followed by the TP-LINK name; unnamed/anonymous clients are labelled accordingly. No remarks are written back to TP-LINK. Refresh reads the existing background cache.
- A recognised TP-LINK wireless client must remain disconnected for **30 seconds**, with a successful observation after that deadline still confirming offline. It then enters the normal notification path without waiting for QWRT or the fork detector's offline timeout.
- A newer reconnect, successful roam or current online record cancels the offline event. The shared cache is checked again before composing an offline notification. Same-second recovery wins over disconnect.
- Missing records alone, expired data, request/log failures or ambiguous status do not confirm a known wireless client offline. Wired/unmanaged devices, a disabled helper and clients not yet identified by a successful collection retain the original detector.
- This works with QWRT native detection enabled or disabled. Existing online discovery, notification switches, filters, Do-Not-Disturb, event batching and send retries remain in effect. TP-LINK clients are not automatically imported into the main device list, so counts may differ.
- Each completed background poll is followed by a roughly 10-second wait. Offline decisions require data at most 30 seconds old. Initial logs cover up to the past 24 hours; subsequent reads are incremental. Delivery includes polling, main-loop and provider latency in addition to the 30-second window. A reconnect after that window can still follow an offline notification.
- Green means connected; red means a connection, credential, configuration or freshness problem; orange means an incompatible API response; grey means loading. The badge shows only the current wireless online count, not historical offline totals.

Tested on **TL-R5005P-AC 1.0, firmware 1.0.4 Build 260414**, with **QWRT 25.12.2**. Other models, firmware and log languages require compatibility checks. The adapter uses local HTTP; passwords, cookies and tokens are excluded from the LuCI cache. Polling may replace an existing web session for the same account. Runtime data is in `/tmp` and rebuilt after reboot. Disable the helper to restore the original offline logic. See [adapter details and tests](docs/tplink-assist.md).

### Other 3.6.20 changes

Revision **r3** isolates each send in a private temporary JSON file to prevent concurrent device/login/scheduled messages from overwriting it or the main loop removing it. WeCom JSON uses ASCII Unicode escapes without changing decoded text. Twelve concurrent 25KB Unicode requests pass the target-QWRT regression with network calls stubbed. The most recent offline title, raw body, payload and timestamp are retained locally in `/tmp/wechatpush/push_diagnostics/` (mode 700), without request URLs or authentication tokens. Only one snapshot is kept; it is overwritten on the next offline notification and lost on reboot.

Fix UTF-8 byte handling on QWRT Bash/musl, exact MAC/IP alias matching and literal percent/quote handling. Prevent stale ARP from undoing a TP-LINK offline decision, reduce unchanged-state writes and prevent dismissed client dialogs from reopening after asynchronous reads. Update WeCom application setup wording and identify image-message logs as `【企业微信图文版】`. For a WeCom API proxy, allow its IP in the application trusted-IP list; for a forward proxy, allow its actual public egress IP. Protocol, UI, original/native detector, alias and UTF-8 regressions now run before package builds and releases.

### Offline detection parameters and MAC list

The offline timeout and detection count in Advanced Settings control offline confirmation. A new “Offline custom detection devices” mode is available in “MAC Filtering Mode 1”. Selecting it reveals the “Offline custom detection list” MAC selector:

- When “Offline timeout applies only to the devices that receive push notifications” is disabled, all devices use the custom timeout and count, including in “Offline custom detection devices” mode.
- Selecting any of the original modes (including “Close”) preserves this fork's original detection-parameter selection and push-filter behavior.
- When the timeout-only-for-push-devices option is enabled and “Offline custom detection devices” is selected, MAC addresses in the list use the custom timeout and count. Devices outside the list, an empty list, or devices whose MAC cannot be obtained use the default detection parameters of **10 seconds and 2 checks**.
- The list selects detection parameters only. It does not change push eligibility; actual notifications remain subject to the existing notification switches and filters.

### Notification content and client information

- Improve device online/offline notification titles and details, and batch state changes detected in the same scan cycle.
- Improve client lists, traffic fields, and layout in WeCom image and plain-text messages.
- Support local IPv4 ip2region XDB lookup and normalized geolocation output.

## Installation and dependencies

The package architecture is `all`. OpenWrt's package manager resolves the required dependencies:

- `iputils-arping`
- `curl`
- `jq`
- `bash`
- `lua`
- `luci-lua-runtime`

To install a package built by this repository's GitHub Actions, download the matching artifact and run, for example:

```sh
opkg install ./luci-app-wechatpush_3.6.20_all.ipk
```

The older SDK records the IPK package version as `3.6.20`. If an earlier revision of that version is already installed, use `opkg --force-reinstall install ./luci-app-wechatpush_3.6.20_all.ipk` for r4 and update the matching language package. APK builds carry the separate `-r4` revision.

Optional dependencies:

- **Local/remote disk information**: `lsblk`, `smartmontools`, and `smartmontools-drivedb`.
- **Remote host information**: `openssh-client` and `openssh-keygen`; configure SSH key-based login first.
- **Email notifications**: Install and configure `msmtp`, or enter SMTP settings in the plugin's mail configuration.

The current GitHub Actions workflow builds an IPK with the OpenWrt 23.05.3 SDK and an APK with the OpenWrt 25.12.0-rc1 SDK. Both CI jobs target x86/64. Although the package itself is architecture-independent, these CI artifacts are not dedicated QWRT ipq53xx/aarch64 builds; use the appropriate SDK to build for other targets.

## Usage notes

- Run `opkg update` before installation or upgrade to refresh package indexes.
- In LuCI, open “Services / WeChat Push”, choose a notification provider, enter its credentials, and enable the service.
- For WeCom trusted-IP restrictions, allow the public egress IP of the configured proxy in the WeCom administration console.
- Enable QWRT-native traffic or online detection only on QWRT 2026.10.6 or later.
- Provide a valid IPv4 ip2region XDB file yourself and enter its actual path in Basic Settings.

## Troubleshooting

When reporting an issue, include the device model, firmware version, package version, and relevant logs. Run:

```sh
/usr/share/wechatpush/wechatpush
bash -x /usr/share/wechatpush/wechatpush t1
```

Also include relevant log or debug files from `/tmp/wechatpush/`. Do not post WeCom Secrets, bot tokens, email passwords, or other credentials in public issues.

## Project links

- This repository: <https://github.com/jarod360/luci-app-wechatpush>
- Upstream project: <https://github.com/tty228/luci-app-wechatpush>

Licensed under GPL-2.0.

Revision **r4** hides the trailing `.lan` suffix (case-insensitive) in automatically detected TP-LINK client display names. Custom aliases remain unchanged.
