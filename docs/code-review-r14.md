# r14 code review (2026-10-28)

## Confirmed findings and fixes

1. The installed router entrypoint still contained pre-r13 diagnostics and eval-based UCI loading. Its menu referenced old preview views. Current master had removed diagnostics and safely assigned UCI values. The previous install therefore did not match current source.
2. OpenWrt 23.05 LuCI sets VERSION from PKG_VERSION without PKG_RELEASE. The r13 artifact still reported 3.6.20. CI now adds -r14 only in the legacy SDK package copy, leaving dependencies and APK metadata unaffected, then verifies the built control metadata and runtime bytes.
3. One-shot configuration and send cleanup reused daemon output/event paths. Private collection directories and serialized scheduled/test sends preserve pending events and avoid rebuilding cron during a test.
4. Pause DND used hour < end to wait, which immediately exited for 23:00–08:00 at 23:00. A shared interval predicate handles daytime, overnight and equal-hour windows.
5. Traffic alerts compared accumulated bytes against a one-minute threshold even when collection took longer. The total and direction deltas now use actual elapsed seconds. The first alert title uses the current device name, and statistics RPCs have bounded duration.
6. Filtering unknown location fields before interpreting positions shifted ISP fields into city slots. Position-preserving parsing covers both legacy zero-placeholder and continent-prefixed records.

## Verification

- Target-router isolated staging: shell/Lua/JSON syntax; 162 UTF-8 boundary checks; 12 login combinations and 599/600-second boundaries; 48 auxiliary/native detector combinations; 32 custom timeout combinations; aliases, host hints, templates and 12 concurrent 25 KB Unicode payloads.
- Added runtime edge checks: literal quote/dollar handling, 96 DND hour boundaries, overnight pause, preservation of pending daemon events and shared output, overlapping-send rejection, skipped-send cleanup, per-minute traffic normalization and alert name.
- Local protocol/UI tests and synthetic XDB tests, including missing province/city fields.
- CI validates and builds both formats; actual IPK version/core bytes are checked before upload. Installation verification compares installed packaged files, configuration backups and service health.

## Scope and limits

Reviewed the r12-to-r13 diff, packaging/service lifecycle, send/login flows, presence gating, traffic collection, Lua protocol/location helpers, UI and ACL integration. This is not a guarantee that every combination of optional remote gateways, SMTP/custom commands, firewall packages or client firmware is covered. No AP aging parameters or offline detection thresholds were changed. Removed diagnostic snapshots remain removed; regression tests are source/CI files, not installed monitoring jobs.

补充：为在线设备流量展示补齐只读的 `luci.client-rates.get` ACL，避免仅授予插件权限的用户看不到流量。
