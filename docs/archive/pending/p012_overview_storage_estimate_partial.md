# p012 概览存储估算只显示一个分段（应用数据）

- 现象：概览「存储估算」五段（系统/应用程序/用户数据/开发者/其他）通常只显示“应用程序”一个数值，其余为“—”，环形图退化为灰色占位。持久缓存 `~/Library/Application Support/zmole/storage_estimate.json` 只含 `applications`（实测 `{"sums":{"applications":32514187794},"capturedAt":813861102.334442,"schemaVersion":1}`，写入时刻 2026-10-17T00:31:42+08:00）。
- 影响：概览存储卡第一屏即展示近似无效的估算（缺段不是“算不出”而是“没算完/算错”）；每次进入概览还会重复触发 2 分钟级后台扫描（`isComplete=false` 使 `estimateNeedsRefresh` 恒真）。
- 根因（两处叠加，均可验证）：
    1. 扫描被取消后仍持久化并回显部分结果（t026 引入）：`OverviewView.swift:24` 的 `.task` 绑定视图生命周期，离开概览即取消；`loadSums()`（`StorageEstimate.swift:100-111`）顺序跑 4 个 probe，取消/中断后剩余 probe 立即失败返回 nil，但 `OverviewViewModel.computeEstimate`（`OverviewViewModel.swift:165-183`）**不检查 `isComplete`/取消状态**，照样 `storageCache.save(sums)` 并置 `estimateInvalidated=false`；下次进入 `primeEstimate`（`:118-123`）把这份部分缓存当权威立即渲染 → 用户看到“只有一个值”。证据：缓存仅含 probe 1（`/Applications` 3.7s 即完成）而 probe 2（`/System`）需 ~129s，部分缓存恰停在 probe 1 之后，说明扫描在 probe 2 期间被取消。
    2. `/System` probe 本身既超时又口径错误（0be6d3e 起）：`mole analyze --json /System` 实测 128.9s（`timeout: 120`，`AppDependencies.swift:430`）→ 超时返回 nil，即使完整跑完也拿不到系统段；且 `/System` 顶层 `Volumes` 项递归包含 `/System/Volumes/Data`（整个数据卷）与快照，实测 `analyze /System` 总和 1.49TB，其中 `/System/Volumes`=1.47TB（真实只读系统卷 `/dev/disk3s1s1` 仅 12GiB）→ 该系统段即使用上也是把数据卷重复计入的伪值，并导致“其他=used-四段”恒为 null。
- 测试缺口：t026 的 `tests/unit/OverviewCacheTests.swift` 全部用“必定完整”的假 loader，未覆盖部分结果/取消/超时；`StorageEstimateLoader` 的 4 路径与 timeout 未测。应补：注入按路径返回 nil 或抛超时错误的假 loader，断言 (a) 不完整 `sums` 不被持久化为可用缓存、不被 `primeEstimate` 当权威渲染；(b) 取消场景不落盘；(c) `/System` 口径修正后系统段数值合理（不包含 `/System/Volumes/Data`）。
- 线索：`.scratch/bug_overview_estimate/`（`cache_partial.json` 实况缓存、`system_analyze.json` 与 `system_top_level.json`：`/System/Volumes`=1614816078217B、`/System/Library`=26205518624B；复现命令 `mole analyze --json /System` 计时 128.9s > 120s timeout）。
- 处理：t034
