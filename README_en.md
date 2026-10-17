# luci-app-wechatpush

[![Build](https://github.com/jarod360/luci-app-wechatpush/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/jarod360/luci-app-wechatpush/actions/workflows/build.yml)
![Version](https://img.shields.io/badge/version-3.6.62-blue)
[![License](https://img.shields.io/badge/license-GPL--2.0-blue.svg)](LICENSE)

[简体中文](README.md) | [English](README_en.md)

## Overview

**luci-app-wechatpush** is an OpenWrt LuCI plugin for network monitoring and notifications. This repository is a maintained fork of [tty228/luci-app-wechatpush](https://github.com/tty228/luci-app-wechatpush). It retains the upstream notification and monitoring functions while adding configurable WeCom API routing, QWRT-native traffic and online detection, IP geolocation lookup, batched device-event notifications, and compatibility fixes.

Current package version: **3.6.62-1**

## Features

- **Network notifications**: Detect IPv4/IPv6 address changes and report network status.
- **Client monitoring**: Track LAN device online/offline status and display connected clients; supports device aliases and MAC vendor information.
- **Batched device events**: Combine device state changes found during one detection cycle into a single notification.
- **Traffic monitoring**: On supported QWRT systems, read native cumulative traffic and trigger abnormal-traffic alerts based on per-minute traffic increments.
- **System and host monitoring**: Monitor router CPU, temperature, and runtime status; retrieve temperature and disk information from remote hosts such as PVE over SSH.
- **Security notifications and protection**: Web/SSH login alerts, automatic banning after failed logins, optional blocking of forwarded traffic from blacklisted IPs, and port knocking.
- **Unattended tasks**: Run configured automation based on device presence, Do-Not-Disturb periods, and other conditions.
- **IP geolocation**: Look up locations for login alerts. IPv4 can use a configured local ip2region XDB database first, with online lookup as fallback. Results are normalized without continent, district/county, ISP, or ASN details.
- **Notification providers**: Server Chan, Server Chan 3, PushPlus, WPUSH, WxPusher, WeCom, Telegram Bot, msmtp email, and custom API templates.

## Main fork-specific changes

The following summarizes the major additions and maintenance changes compared with the upstream repository. Exact behavior is defined by the current source code.

### WeCom API and proxy

- Configure a custom WeCom API Base URL; when empty, the official API endpoint is used.
- Configure an HTTP/SOCKS forward proxy. WeCom token retrieval, media upload for image messages, and message sending all use the configured proxy.
- The API Base URL selects the destination host, while the proxy selects the network route; they are independent settings.

### QWRT-native features

These options require **QWRT 2026.10.6 or later** and are enabled separately under Basic Settings:

- **QWRT native traffic statistics**: Reads cumulative traffic through `luci.client-rates get`. The data is used for online-device information, device notifications, abnormal-traffic alerts, and unattended low-traffic checks. This implementation no longer depends on or calls the legacy `wrtbwmon`.
- **QWRT native online detection**: Determines client state using the ARP/MAC rules used by the QWRT LuCI overview. It does not send active ping/arping probes. Because it relies on the current ARP table, sleeping clients or clients without a valid ARP entry may be reported offline.

Both QWRT options are independent and disabled by default. Do not enable them on non-QWRT systems.

### Offline detection parameters and MAC list

The offline timeout and detection count in Advanced Settings control offline confirmation. The “Offline custom detection list” in “MAC Filtering Mode 1” can select which MAC addresses use those custom parameters:

- When “Offline timeout applies only to the devices that receive push notifications” is disabled, all devices continue to use the custom timeout and count; the new list does not change this behavior.
- When that option is enabled but the new list switch is disabled, parameter selection follows this fork's original push-filter logic.
- When both switches are enabled, MAC addresses in the list use the custom timeout and count. Devices outside the list, an empty list, or devices whose MAC cannot be obtained use the default detection parameters of **10 seconds and 2 checks**.
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
opkg install ./luci-app-wechatpush_3.6.62-1_all.ipk
```

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
