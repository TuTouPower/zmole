---
tid: "t028"
slug: "disk_incremental_scan"
title: "磁盘页增量扫描与交互改造"
status: "done"
branch: "t028_disk_incremental_scan"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "3d42958b84fbfc08d96a24d20b3a8613ee31f3a6"
depends_on: ""
conflicts_with: ""
note: "用户 2026-10-17 批准（原 t028；合并 t032 的交互/百分比列）。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

- 2026-10-17 磁盘页改为应用内只读扫描：新增 `DiskScanner.swift`（`DiskScanning` 协议 + `LiveDiskScanner`）。文件按 `lstat` 的 `st_blocks × 512`；符号链接只计自身；硬链接经 `HardLinkDeduplicator` 同一扫描只计一次；跨设备子目录标记 `otherDevice`、不计入父合计、进入后单独测量。目录合计只含后代文件的分配块（不含目录 inode 自身块），保证临时目录测试可精确断言。
- `AnalyzeViewModel` 重写为注入式目录源 + 会话缓存：进入目录立即列举，子目录大小按队列逐个后台补上；父目录测量会带回子树各层的名单（`DiskScanResult.levels`），此后进入子目录直接读缓存，只有 `refreshCurrent`（重新分析）才重扫当前目录及其子树。`generation` 计数使旧代在飞结果失效，不覆盖重新分析结果。
- 磁盘页不再走 mole：`MoleCommandLanes` 删除 analyze 通道（9→8），`MoleCommandLanes`/`CommandConcurrencyTests` 相应更新；`AnalyzeSnapshotLoader` 移入 `AnalyzeSnapshot.swift`，仍供概览五段估算使用。
- 交互：左右分隔可拖动（`DiskSplitLayout` + `DragGesture`）；删除列表行右侧「进入目录」按钮，列表行与地图方块双击进入目录；列表大小紧跟文件名加「占父目录」百分比列与柱状条；行内展开树移除（进入目录统一为下钻，替换原展开交互）。
- demo：新增 `DemoDiskScanner` 内存目录源（populated/empty/error/partial 状态；partial 保留一个计算中的子树），demo 不再用 analyze fixture 驱动磁盘页。
- 测试按其语义调整：`DiskExplorerTests` 重写为注入目录源的新语义；新增 `DiskScannerTests`（真实临时目录验证分配块、符号链接、硬链接、不可读目录与会话缓存）；`RecoverableBusyTests` 删除两条磁盘页 mole busy 用例（该页不再 spawn mole，理由见文件注释）；`SpaceMapTests` 换用 `DiskEntry`。
- 黑盒（demo smoke）：Debug 构建 `--demo --demo-page disk` 浅色 zh-Hans 与深色 en 截图各一张，fixture、百分比列、柱形条、面积图与合计均正常；无删除控件。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-10-17T01:45:00+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t028_code_f001|minor|已修|三处子路径拼接统一复用 `LiveDiskScanner.childPath` / `directoryPrefix`|src/zmole/Features/Analyze/AnalyzeViewModel.swift:220|
|t028_code_f002|minor|已修|采纳口径 b：维持「同一扫描硬链接只计一次」并在 blueprint 写明跨层语义（行显示自身块、父扫描已计入则子层合计不重复计入）|docs/blueprint/architecture.md|
|t028_test_f001|important|已修|补回 reveal 转发、面包屑 `open(path:)` 回跳、名称排序、列表失败与返回四条覆盖|tests/unit/DiskExplorerTests.swift|
|t028_test_f002|minor|已修|AC-012 测试增加装配点断言：生产装配 `LiveDiskScanner`、demo 装配 `DemoDiskScanner`|tests/unit/DiskExplorerTests.swift|

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足（19/19 AC，见 `handoff.json` 的 `ac_evidence`）
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'` 212 通过（含 DiskExplorerTests 22、DiskScannerTests 5）；`pytest .repo_template/tests -q -m contract` 147 通过；`tests/integration/clean_trash_test.sh` 与 `tests/integration/installer_interface_test.sh` 通过
- 黑盒：demo smoke（`--demo --demo-page disk --demo-state populated`，浅色 zh-Hans 与深色 en 截图）显示 fixture、大小紧邻文件名、占父目录百分比列与柱形条、面积图与 78.05 GB 合计；无删除或废纸篓控件
- review：full 双轴 Round 2 PASS；`reviewed_scope 70d19f4c797abae5`；无未解决 finding
- AC 证据：见 `handoff.json`

### 结果摘要

- 磁盘页改为应用内只读增量扫描与会话内层级缓存：进入先列直接子项，子目录大小后台逐个补上，已扫描层级再进入不再读盘，只有「重新分析」重扫；扫描不调用 mole。
- 交互改造：列表大小紧跟文件名、新增「占父目录」百分比列与柱形条、左右两栏可拖动、删除行内「进入目录」按钮、行与容量方块双击下钻。
- 遗留：无
