# TP-LINK 无线客户端辅助检测（3.6.20）

## 使用与兼容性

先启用 WeChatPush 服务，再在基础设置的 QWRT 原生在线检测下方启用 TP-LINK 辅助检测。
填写管理 IPv4、用户名和密码，保存并应用。无需 SSH、Home Assistant 或改变 TP-LINK 配置。
已验证 TL-R5005P-AC 1.0 / 固件 1.0.4 Build 260414 与 QWRT 25.12.2。
其他型号、固件或日志语言未承诺兼容。当前使用局域网 HTTP 管理 API。

绿色按钮显示“无线客户端在线 N”，点击打开“TP-LINK 在线客户端”弹窗。
桌面显示名称、IP、MAC、AP、SSID；767px 及以下只显示名称、IP、AP。
名称按 WeChatPush MAC 别名、IP 别名、QWRT 主机名、主设备表名称、TP-LINK 名称、未命名的顺序选择。
不会修改 TP-LINK 设备备注。刷新只读现有缓存，不发起额外登录。
红色表示连接、凭据、配置、日志或缓存有效性异常；橙色表示返回格式不适配。

## 离线流程

1. 根据客户端类型 `wireless` 与 `[WSTATION]` 事件识别无线 MAC，显式 `wired` 类型优先排除。
2. 主客户端表明确在线优先。无线 MAC 消失时，只能由最近的明确断开记录补充离线状态。
   不把“查不到 MAC”直接当作离线，也不使用比上次已知在线观测更早的断开记录。
3. 断开记录启动 30 秒确认窗口。新的断开可能重置窗口；接入、漫游或在线状态取消离线。
   同一秒既有断开又有恢复时，优先恢复，避免依赖日志的同秒排序。
4. 30 秒结束后必须再次成功读取，最新状态仍离线，且缓存不超过 30 秒，才进入原有离线通知流程。
   已识别无线设备不再等待 QWRT/原 fork 的超时与重试计数。残留本地 ARP 不得撤销该离线判定。
5. 生成离线通知详情前再次检查最新缓存。状态不明、读取失败、日志不可用、过期或缺少断开时间则暂缓。
6. 有线、未识别的设备以及未启用辅助检测时，保留原检测方式。
   缓存尚未初始化、尚无无线识别信息时也使用原检测，避免首次连接失败拖住所有有线设备。

支持 QWRT 原生检测开启/关闭两种情况。上线发现、通知开关、黑白名单、免打扰、
事件合并、失败重试和流量功能保留原路径。不会把 TP-LINK 列表导入主设备表。
两处列表数量因此可能不同。辅助检测失联期间，已识别无线设备的离线推送可能延迟；
恢复连接或关闭辅助即可解除。30 秒是确认窗口，实际送达还叠加采集、主循环和通道耗时。
重连超过窗口仍可能收到离线通知，不能保证排除所有长时间漫游/重连。

## 采集、开销与凭据

`tplink-monitor` 为独立 procd 任务，完成一轮后等待 10 秒。独立任务不在时主扫描才按需回退采集。
同机采集通过目录锁串行化，认证失败等待 60 秒重试。凭据不经过主脚本的 shell eval。
每次会话登录、读取 `host_management.host_info`、读取无线日志，再登出。
首次最多读取最近 24 小时日志（每页 500，最多 10 页）；后续从上次检查时间减 2 秒开始增量读取
（每页 100，最多 10 页）。请求超时受限；不能确认的客户端保留未知状态。

状态缓存 `/tmp/wechatpush/tplink_status.json` 原子替换，只含设备信息、MAC 状态、
确认时间及无线事件；不含密码、Cookie 或登录令牌。请求体和会话文件保存在权限 700 的独立临时目录。
缓存只在 RAM 中，不按轮询写闪存。界面不展示历史离线总数。
已知无线 MAC 在当前运行缓存中保留，以免断开后被误当作有线设备；重启后重新建立。
正常在线且状态无变化时不重复重写主设备表。轮询可能挤掉 TP-LINK 同账号网页会话。

协议常量与编码行为可对照 TP-LINK Web 登录实现及以下开源实现；本项目以独立 Lua 模块实现：

- https://github.com/AlexandrErohin/TP-Link-Archer-C6U/blob/main/tplinkrouterc6u/client/r.py
- https://github.com/AlexandrErohin/TP-Link-Archer-C6U/blob/main/tplinkrouterc6u/client/xdr.py

## UTF-8 与别名修复

QWRT Bash/musl 对原始 UTF-8 单字节执行 `printf '%d'` 时可能返回 U+DFxx 数值，
如字节 E4 返回 57316。原宽度和裁剪函数因此可能切断 UTF-8 字符。
读取数值后取低 8 位，保持中文、箭头和 emoji 的边界。
别名使用精确 MAC/IP 匹配并按字面输出，避免 `%` 被当作格式串；新设备 JSON 使用 `jq --arg` 编码。

## 开发测试

Python 开发测试依赖 `lupa==2.8`，不是路由器运行依赖。
Linux 测试环境还需 Bash、jq、Lua 5.1 和 Node.js。

```sh
python tests/test_ip2region.py
python tests/test_tplink.py
node tests/test_tplink_ui.js
bash tests/test_tplink_down.sh
bash tests/test_device_aliases.sh
bash tests/test_utf8.sh
bash tests/test_template_utf8.sh
bash tests/test_push_concurrency.sh
```

Shell 测试提取函数到临时目录，使用假设备记录；企业微信模板测试替换网络及发送函数，只生成 JSON。
UTF-8 测试应额外在目标 QWRT 的 Bash/libc 上执行，普通 glibc 环境可能无法复现旧问题。
GitHub Actions 先验证完整源码语法及回归测试，通过后构建 IPK/APK；`v*` 标签构建成功后发布。
