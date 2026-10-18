# p021 概览存储估算因 100MB 临时库配额超限与全量建表导致持续无结果

- 现象：生产环境下打开“概览”页面，“存储估算”始终显示“估算不完整，缺失分段显示为「—」”，全部五个分段（系统、应用程序、用户数据、开发者、其他）持续无结果，并伴随持续 200%~300% CPU 占用与每 60 秒重复重试死循环。
- 影响：概览核心存储估算功能全面不可用，后台进程陷入高负荷文件 I/O 与 SQLite 写入死循环。
- 根因：产品架构设计与配额缺陷，已在真实环境精准复现（`.scratch/test_quota_fail.swift` 与 `.scratch/reproduce_estimate_bug.swift`）。
    1. **100MB 临时配额与真实规模冲突（直接中断根因）**：`t058` 将概览估算改接 `DiskMeasurementSession`，底层走 `LiveDiskScanner` + `DiskSessionStore`（SQLite 全量文件入库）。`DiskSessionStore` 硬编码限制 `maxStorageBytes = 100MB` 并由 `DiskStorageBudget` 聚合检查。在真实 Mac 上，仅 `/Applications` 就包含数万文件，写入至约 2.3 万条 entries（约 102MB 数据库+日志）时即触发 `DiskStorageBudget.check()` 抛出 `storageQuotaExceeded` 异常。测量任务被强行回滚终止，`measureSubtreeOutcome` 提前返回 `(size: nil, isReadable: false)`。`/Users` 与 `/System/Library` 同样会在中途超限抛错，导致概览所需的所有分段全部为 `nil`。
    2. **概览聚合与磁盘全量建表职责混淆**：磁盘分析页需要逐级展开与 treemap 面积图，故需每文件建表；概览仅需粗粒度子树分配块合计与 Developer 归属，强行走完整 SQLite 索引导致不必要的磁盘写膨胀与 $O(N^2)$ SQL 遍历。
- 已确认同类位点：
    - `DiskMeasurementSession.measureSubtreeOutcome`：凡是请求大目录（如 `/Applications`、`/Users`、`/System/Library`），均必然击穿 100MB 配额导致结果为 `nil`。
    - `OverviewViewModel.scheduleIncompleteRetry`：失败无退避，每 60 秒定时重跑，加剧持续 CPU/磁盘负载。
- 测试缺口：既有单测（`OverviewUnifiedMeasureTests` 等）均使用 10~20 个小文件的微型临时夹具（SQLite 仅几 KB），未能模拟真实机器上万文件的存储规模与 100MB 配额边界，造成测试假绿。
- 线索：`.scratch/test_quota_fail.swift`（真实 `/Applications` 49 秒写入超限 100MB 抛出 `storageQuotaExceeded` 复现脚本）、`.scratch/reproduce_estimate_bug.swift`（`measureSubtreeOutcome` 59 秒返回 `(size: nil, isReadable: false)` 复现脚本）。
- 修复：2026-10-18 在 main 直接改。生产概览改为 `LiveDiskScanner` 流式合计（`SubtreeAccumulator`），不把逐文件写入 `DiskSessionStore`。`/Users` 一次遍历同时得到用户总量和 Developer 归属；磁盘页已有新鲜完整摘要时直接复用。Developer 不存在按 0，该目录本身不可读则开发者段与用户段都不可用，其它不可读后代只跳过该支。整次扫描没有任何分段时不覆盖已有缓存，也不排 60 秒补扫。磁盘页 100MB 配额未改。ADR 015。
- 处理：main
