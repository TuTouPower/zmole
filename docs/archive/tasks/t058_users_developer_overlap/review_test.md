# Task review t058（reviewer_focus: 测试）

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
- 测试策略与可信度核查：
  - 测试隔离：`OverviewUnifiedMeasureTests` 包含 8 个针对性单元测试，在临时文件系统与可观测 session 夹具上进行，无对宿主机物理磁盘的全盘递归扫描。
  - 真实测量语义：覆盖直接文件、隐藏文件、跨目录硬链接、无 FDA 隔离、并发取消与会话共享。
  - 资源基准：`testAC010_Deploy_BenchmarkFinalUnifiedBackend` 完成名额 1、2、3、4 的 5 轮交错测量（Budget 1: avg=0.0241s, Budget 2: avg=0.0126s, Budget 3: avg=0.0119s, Budget 4: avg=0.0123s），证明多名额有效性并确认生产默认名额 3。
  - 回归保护：全量 374 个单元测试全绿，4 个集成测试全绿，pytest contract 测试全绿。
- 总体判断：测试充分有效，完全覆盖 spec 验收标准。

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
