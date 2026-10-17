# luci-app-wechatpush

[![Build](https://github.com/jarod360/luci-app-wechatpush/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/jarod360/luci-app-wechatpush/actions/workflows/build.yml)
![Version](https://img.shields.io/badge/version-3.6.19-blue)
[![License](https://img.shields.io/badge/license-GPL--2.0-blue.svg)](LICENSE)

[简体中文](README.md) | [English](README_en.md)

## 项目简介

**luci-app-wechatpush** 是一个 OpenWrt LuCI 网络监控与消息通知插件。本仓库是基于上游 [tty228/luci-app-wechatpush](https://github.com/tty228/luci-app-wechatpush) 持续维护的 fork，在保留原有通知、监控及 HTTP/SOCKS 正向代理等 fork 功能的基础上，进一步扩展了 QWRT 原生流量与在线检测、IP 归属地查询、设备事件合并推送及多项兼容性修复。

当前软件包版本：**3.6.19-1**

## 主要功能

- **网络状态通知**：检测路由器 IPv4/IPv6 地址变化，并推送网络状态。
- **终端设备监控**：检测局域网设备上线、离线，显示在线设备及相关信息；支持设备别名和 MAC 厂商信息。
- **设备事件合并推送**：同一轮检测发现的多台设备状态变化会合并为一条通知，减少设备集中上下线时的消息数量。
- **流量监控**：在支持的 QWRT 系统上读取原生累计流量，显示设备流量，并支持按每分钟流量增量触发异常流量告警。
- **系统与主机监控**：监控路由器 CPU、温度及运行状态；可通过 SSH 获取远程主机（例如 PVE）的温度和磁盘信息。
- **安全通知与防护**：Web/SSH 登录提醒、失败登录自动封禁、黑名单转发流量拦截，以及端口敲门。
- **无人值守任务**：支持按设备在线状态、勿扰时段等条件执行配置的自动化任务。
- **多种通知渠道**：支持 Server 酱、Server 酱 3、PushPlus、WPUSH、WxPusher、企业微信、Telegram Bot、msmtp 邮件，以及自定义 API 模板。

## 保留的原有 fork 功能

- **企业微信 HTTP/SOCKS 正向代理**：可配置 HTTP/SOCKS 正向代理，企业微信获取 Token、上传图文封面素材和发送消息均使用该代理。这是原有 fork 已具备的功能，并非本次新增扩展。

## 本仓库的主要扩展

以下是相对于上游仓库的主要扩展和维护改动，具体行为以当前源码为准：

### IP 归属地查询扩展

- 登录提醒可查询 IP 地理位置。
- IPv4 支持配置本地 ip2region XDB 数据库作为优先查询来源，未命中时回退在线查询。
- 显示结果会进行层级归一化，不显示大洲、县区、运营商或 ASN。

### 企业微信 API 地址配置

- 可配置企业微信 API Base URL；留空时使用官方 API 地址。

### QWRT 原生功能

仅适用于 **QWRT 2026.10.6 及以上版本**，在“基础设置”中分别启用：

- **QWRT 原生流量统计**：使用 `luci.client-rates get` 获取累计流量，供在线设备信息、设备通知、异常流量告警及无人值守低流量判断使用。该实现不再依赖或调用旧版 `wrtbwmon`。
- **QWRT 原生在线检测**：按 QWRT LuCI 概览使用的 ARP/MAC 规则判断设备在线状态，不发送 ping/arping 主动探测。该方式依赖当前 ARP 表，休眠设备或没有有效 ARP 记录的设备可能被判定为离线。

两个 QWRT 选项相互独立，默认关闭。非 QWRT 系统不要启用。

### 离线检测参数与 MAC 名单

高级设置中的离线超时和检测次数用于控制设备离线确认。在“MAC 过滤模式一”中新增“离线自定义检测设备”模式；选择该模式后，下方显示“离线自定义检测列表” MAC 选择框：

- “离线超时仅针对推送设备”关闭时，原有模式仍由所有设备使用自定义超时和次数；但如果选择了新增的“离线自定义检测设备”模式，则按该模式的 MAC 名单选择检测参数。
- 选择其他原有模式（包括“关闭”）时，完全沿用本 fork 原有的检测参数选择和推送过滤逻辑。
- 选择“离线自定义检测设备”模式后，名单内 MAC 使用高级设置中的自定义超时和次数；名单外、空名单或无法获取 MAC 的设备使用默认检测参数 **10 秒、2 次**。
- 该名单只选择检测参数，不改变设备的推送资格；实际通知仍遵循原有通知开关和过滤规则。

### 通知内容与设备信息

- 优化设备上下线通知标题和详情；同一轮检测中的设备状态变化合并推送。
- 优化企业微信图文与纯文字消息的设备列表、流量字段及排版。
- 支持本地 IPv4 ip2region XDB 查询，并对归属地结果进行规范化显示。

## 安装与依赖

软件包架构为 `all`。安装时由 OpenWrt 软件包管理器处理依赖。基础依赖：

- `iputils-arping`
- `curl`
- `jq`
- `bash`
- `lua`
- `luci-lua-runtime`

使用本仓库 GitHub Actions 构建产物时，下载对应的软件包后安装，例如：

```sh
opkg install ./luci-app-wechatpush_3.6.19-1_all.ipk
```

可选依赖：

- **本地/远程磁盘信息**：`lsblk`、`smartmontools`、`smartmontools-drivedb`。
- **远程主机信息**：`openssh-client`、`openssh-keygen`，并提前配置 SSH 密钥登录。
- **邮件通知**：安装并配置 `msmtp`；也可在插件的邮件配置项中填写 SMTP 参数。

本仓库当前 GitHub Actions 工作流分别使用 OpenWrt 23.05.3 SDK 构建 IPK、OpenWrt 25.12.0-rc1 SDK 构建 APK，构建目标为 x86/64。软件包本身为架构无关包，但上述 CI 产物不代表已提供 QWRT ipq53xx/aarch64 专用构建；其他目标平台请使用对应 SDK 自行编译。

## 使用说明

- 首次安装或升级前，可先执行 `opkg update` 更新软件包索引。
- 在 LuCI 的“服务 / 微信推送”页面选择通知方式并填写对应凭据，再启用服务。
- 使用企业微信时，可信 IP 白名单仍由企业微信管理后台控制；如配置正向代理，应放行代理服务器的公网出口 IP。
- 启用 QWRT 原生流量或在线检测前，请确认设备运行的是 QWRT 2026.10.6 或更新版本。
- 本地 ip2region 数据库需自行准备有效的 IPv4 XDB 文件，并在基础设置中填写实际路径。

## 故障排查

提交问题时请附上设备型号、系统版本、软件包版本，以及相关日志。可在路由器上执行：

```sh
/usr/share/wechatpush/wechatpush
bash -x /usr/share/wechatpush/wechatpush t1
```

同时提供 `/tmp/wechatpush/` 中与问题相关的日志或调试文件。请勿在公开 issue 中粘贴企业微信 Secret、Bot Token、邮箱密码等敏感凭据。

## 项目地址

- 本仓库：<https://github.com/jarod360/luci-app-wechatpush>
- 上游项目：<https://github.com/tty228/luci-app-wechatpush>

本项目遵循 GPL-2.0 许可证。
