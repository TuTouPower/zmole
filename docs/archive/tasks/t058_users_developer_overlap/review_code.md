# Task review t058（reviewer_focus: 代码）

- task：`t058_users_developer_overlap`
- spec：`docs/tasks/t058_users_developer_overlap/spec.md`
- diff_anchor：`4e6a7b02451bae4fc43e02b064bc49c94c3dfccc`
- target：`git -C '/Users/karson/kar/code/zmole_t058' diff 4e6a7b02451bae4fc43e02b064bc49c94c3dfccc`
- round：1
- reviewed_at：2026-10-18T04:56:00+08:00

reviewed_scope: 46da0104eae79a0a

## Findings

Round 1 零 finding

## 结论

- 前轮 finding 复核：Round 1，无前轮。
- 本轮新发现：0 条。
- 架构与实现核查：
  - 统一测量复用：`StorageEstimateLoader` 支持注入 `DiskMeasurementSession`，一轮 `/Users` 遍历同时获取包含 Developer 的用户总量及当前用户 `Library/Developer` 命名子树统计，消除独立 Developer 重遍历与旧 `estimatePool` / analyze 目录命令通道。
  - 分类归属明确：当前用户 Developer 拥有优先归属；跨 Developer 与其他用户路径的硬链接在 users 范围只计一次且归属 Developer；显示用户数据为 users 去重总量减 Developer 贡献（非负且相加等于 users 总量）。
  - 会话能力完备：`DiskMeasurementSession` 扩展 `measureSubtreeOutcome` 及 `isSubtreeReadable`，支持等待与提取命名子树测量结果；取消与会话生命周期一致。
  - 缓存与权限生命周期：`StorageEstimateCache.schemaVersion` 升级为 3，旧 schema 1/2 缓存整体丢弃重算；无 FDA 时不遍历 `/Users`，此时允许独立测量可读的 Developer 子树。
- 总体判断：代码严谨遵循规范，完全满足所有 AC 要求，无未解决 finding。

### AC 复验方式

- AC-002：`testAC002_UsersAndDeveloperAttributionMatchesContract` 验证同快照 users=100、Developer=30 时，用户段=70、开发者=30；Developer=0 时用户段=100。
- AC-003：`testAC003_SystemVolumesExcludedAndFailureMakesSystemUnavailable` 验证 /System/Volumes 不遍历且任一系统子项失败系统不可用。
- AC-004：`testAC004_SingleWalkOfUsersMeasuresBothUsersAndDeveloperWithoutSecondWalk` 验证完整估算只单次遍历 users，无独立 Developer 重遍历或 analyze 命令。
- AC-005：`testAC002_UsersAndDeveloperAttributionMatchesContract` 与 `DiskMeasurementSession` 语义覆盖直接文件、隐藏项与子目录统计。
- AC-006：`testAC006_CrossDirectoryHardlinkAttributedToDeveloper` 验证跨目录硬链接计入 Developer，逆转完成顺序分段一致。
- AC-007：`testAC007_NoFDAWalksDeveloperOnlyIfReadable` 验证无 FDA 不遍历 /Users，可独立测量 Developer，失败不伪装成 0。
- AC-008：`testAC008_OverviewAndDiskShareSameSessionAndActualWalk` 验证概览与磁盘共用 session，取消一方不破坏另一方。
- AC-009：`testAC009_Schema2CacheIsDiscardedAndSchema3IsAuthoritative` 验证 schema 2 缓存被丢弃，schema 3 为权威。
- AC-010：`testAC010_Deploy_BenchmarkFinalUnifiedBackend` 验证名额 1、2、3、4 对照测试，确认生产默认并发名额 3 稳健适用。
- coverage = 9/9

verdict: PASS
