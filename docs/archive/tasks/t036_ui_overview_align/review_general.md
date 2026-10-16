# Task review t036（reviewer_focus: 通用）

- task：`t036_ui_overview_align`
- spec：`docs/tasks/t036_ui_overview_align/spec.md`
- diff_anchor：`72fbd36a15c3f7491806384dbdf84f2410a66abd`
- target：`git -C '/Users/karson/kar/code/zmole_t036' diff 72fbd36a15c3f7491806384dbdf84f2410a66abd`
- round：1
- reviewed_at：2026-10-17T04:52:00+08:00

## Findings

### t036_gen_f001 - 「系统」段子项探测失败被静默丢弃，部分和落盘并当作权威估算

- 严重度：important
- 锚点：契约区范围「扫描被取消或未完成时，不把不完整结果持久化为可用缓存，不据此渲染为权威估算」；与 `docs/blueprint/architecture.md:83`「只有完整扫描（四个路径全部可读）才落盘」及 `task.md` 实施笔记「仅在四路径齐全时落盘」自述不符
- 位置：`src/zmole/Features/Overview/StorageEstimate.swift:137-154`（`systemSize`，关键 146-153）；落盘路径 `src/zmole/Features/Overview/OverviewViewModel.swift:386-389`
- 问题：`systemSize` 只要求「至少一个子项成功」（`readAnything`，第 145/149/153 行）即把部分和作为完整值返回。`directorySize` 对「目录子项读取失败」（mole 非零退出/JSON 解析失败/120s 超时）与「子项是普通文件」返回同样的 nil，实现无法区分二者。失败场景：某次扫描中 `/System/Library`（本机实测 5.28s，/System 最大子项）探测失败而其余子项成功 → 系统段少算约 12 GiB（`其他` 段相应虚增），但 `StorageSums.isComplete == true` → `computeEstimate` 落盘缓存并接替展示，`estimateNeedsRefresh` 在 TTL（6h）内不再重试 → 错误值被当作权威估算展示。该口径正是本 task 要修的缺陷类别（p012 的只含 applications 缓存）在系统段子项粒度上的残留。混合成功/失败分支无任何测试覆盖：`tests/unit/OverviewCacheTests.swift:144` 只覆盖「唯一子项失败」，`:228` 只断言跳过 `/System/Volumes`。
- 建议：按目录性区分失败——`systemChildren` 用 `contentsOfDirectory(at:includingPropertiesForKeys:[.isDirectoryKey])` 只返回目录子项，`systemSize` 对任一目录子项探测失败返回 nil（该段不可用：不落盘、下次进入重试），补一条「一子项失败、另一子项成功」用例。若有意放宽为「部分和也算完成」，须在 spec/blueprint 写明并补断言该语义的测试。

### t036_gen_f002 - 「刷新」按钮不保证触发一次新的状态重采样

- 严重度：minor
- 锚点：AC-001「点击刷新触发状态重采样」（同义记于 `docs/design/ui_contract.md:26`）
- 位置：`src/zmole/Features/Overview/OverviewView.swift:50-54`；`src/zmole/Features/Status/StatusViewModel.swift:157-162`；`src/zmole/Features/Status/StatusWatchService.swift:141-142`
- 问题：刷新按钮调用 `statusViewModel.retry()`，其效果是取消当前监听任务并重新订阅 + `start()`；watch 进程已在运行时 `startProcessIfNeeded` 被 `processTask == nil` 挡住直接返回，不产生新采样（是否重启取决于旧订阅移除与新订阅的竞态，健康态多数不重启）。即该点击只是「手动恢复/重订阅」，不保证「触发重采样」；因 watch 本就 1s 实时采样，正常态用户看得出来吗——看不出（这也是影响低的原因）。旁证：t035 状态页 `status.refresh` 同用 `retry()` 且在采样中禁用（`StatusView.swift:45-46`），本页未禁用。
- 建议：二选一——规范/`ui_contract` 表述改为「手动恢复（重订阅）」，或让点击强制重采样（先停再起/服务端提供 force restart）。

### t036_gen_f003 - 最近活动行 id 可能重复

- 严重度：minor
- 锚点：行为缺陷（潜在）；AC-005 行结构
- 位置：`src/zmole/Features/Overview/OverviewViewModel.swift:188-197`（`OverviewActivityRow.make`）
- 问题：行 id = `command|dateText|size`（不含 `items`）；两条 command、结束时间（秒级精度）、size 完全相同的会话产生重复 id，SwiftUI `ForEach` 对重复 id 行为未定义（可能丢行/警告）。概率低（需同一秒结束且 size 相同），但旧实现用 `enumerated()` 序号无此风险。
- 建议：id 纳入全部展示字段（含 items），或用稳定序号。

### t036_gen_f004 - 重排后遗留的无用定义与本地化键

- 严重度：minor
- 锚点：架构与可维护性（本 diff 抹掉最后生产引用后未清理；AGENTS「删除因自己修改而无用的 import/变量/函数」）
- 位置：`src/zmole/Features/Overview/OverviewViewModel.swift:18-26`（`memoryText` 生产零引用，仅 `tests/unit/OverviewTests.swift:90` 断言非空）；`src/zmole/Resources/Localizable.xcstrings:235`（`overview.memory` 键零引用，清理旧键时漏删）；`src/zmole/Features/Overview/OverviewViewModel.swift:3`（新增 `import SwiftUI`，本文件无任何 SwiftUI 符号）
- 问题：健康卡改为 可用磁盘/可回收/CPU 三 tile、四宫格另行内联内存格式化（`OverviewViewModel.swift:143-154`）后，`memoryText` 与 `overview.memory` 失去最后用户；属本 diff 自产残留。
- 建议：删除 `memoryText`/`overview.memory`/未用 import 并调整对应测试断言；或让四宫格复用 `memoryText` 消除重复格式化逻辑。

### t036_gen_f005 - architecture.md「用四次 analyze 目录求和」已过时

- 严重度：minor
- 锚点：文档一致性（非 AC）
- 位置：`docs/blueprint/architecture.md:81`
- 问题：系统段已改为按 `/System` 顶层子项逐个 `analyze`（本机 6 个可用子项合计约 7.5s），同段却仍写「用四次 analyze 目录求和」，且后半句又写「逐项求和」，自相矛盾（实为固定 3 次 + N 次子项）。
- 建议：改为「三次固定目录 + 系统段按顶层子项逐项 analyze（跳过 `/System/Volumes`）」。

## 结论

- 本轮新发现：5 条（1 important / 4 minor）
- 未进表的提示：
    - 活动行「时间」直接渲染 `ended_at` 原始 ISO 8601（`OverviewViewModel.swift:193`、`OverviewView.swift:318`），demo `activityRow` 显示「2 天前」等友好时间；AC-005 未规定格式、历史页同为原始串（既有惯例），未进 finding，建议 finalization 时与 demo 对照裁定。
    - 视觉类 AC-008 依赖 `--demo` 截图；工作区未见截图产物（`.scratch/ui_rebuild` 仅 `demo_data/`），`task.md` 的「截图核对」自述无法独立核验，建议合并前人工抽查。
    - `AppDependencies.swift:169-173` 的 `dataVolumeAnalyzeFixture` 为防御性死夹具（loader 已跳过 `/System/Volumes`，永不触发），保留可接受。
    - 变更规模 14 文件 +885/−297，属单 task 合理范围；`OverviewView.swift` 409 行未超阈值。
    - 流程提示（非本 task 代码问题，报用户）：`.repo_template/scripts/repo_task/review.py:239` 的 `reported_findings()` 只提取行首（可带 `|`）的 finding_id，而 review prompt 模板要求的 `### tNNN_gen_fNNN - 标题` 不匹配 `^\|?\s*` 锚点，导致 `check_review_status.py` 的处置表缺失检查（missing_disposition）对此格式报告恒为空。未自行改工具，按模板输出。
- 总体判断：实现主体符合契约（AC-002～007、009～012 按代码与单测复验，独立重跑 268 例 0 失败），但 f001 的系统段「子项失败静默降级为部分和并落盘」违反「不完整不落盘/不作权威」不变量，为未解决 important，本轮 FAIL。
- 系统性 follow-up：无（f001 建议本 task 内修复；若判定有意放宽，改 spec/blueprint 并补测试）

### AC 复验方式

- AC-001 re_verified：按钮与动作接线按代码复验（`OverviewView.swift:44-68` → `statusViewModel.retry()` / `navigation.select(.clean)`；`lastReclaimBytes` 为空走纯入口文案）；「重采样」语义偏差见 f002。
- AC-002 re_verified：`OverviewHealthCard.make`（`OverviewViewModel.swift:88-125`）不可用分显示「—」，圆环无值时不画弧（`OverviewView.swift:123-147`）；`testHealthCardShowsPlaceholdersWithoutSamples` 等通过。
- AC-003 re_verified：三 tile 值来自 snapshot/`cleanViewModel.lastReclaimBytes`；`testHealthCardUsesRealValuesAndPlaceholdersForMissingSources` 通过。
- AC-004 re_verified：`testStorageCardBuildsSegmentsAndFreeSpace`、`testStorageCardReportsIncompleteEstimate` 通过；不完整文案 `OverviewView.swift:212-216`。
- AC-005 re_verified：`testActivityRowsMapHistorySessionsInOrder`、`testActivityRowsAreEmptyWithoutHistory` 通过；空态 `OverviewView.swift:291-295`。
- AC-006 re_verified：`testStatusGridMapsRealSamplesAndPlaceholders`、`testStatusGridWithoutSampleShowsOnlyPlaceholders` 通过。
- AC-007 re_verified：`OverviewQuickAction`/`OverviewTrend`/环形图/柱条视图已删，`rg` 零命中；`testOverviewDroppedQuickCardsAndTrend` 通过。
- AC-008 trust_prior：深浅色/三语/1200×780 与 1100×700 裁切需 GUI 截图，工作区无产物，依赖实施侧 task.md「demo 截图核对」自述。
- AC-009 re_verified：`testCancelledScanDoesNotPersistAnything` 通过；取消路径 `computeEstimate` catch（`OverviewViewModel.swift:399-404`）+ bridge cancelled→CancellationError 映射（`StorageEstimate.swift:105-106`）按代码复验。
- AC-010 re_verified：`testStorageEstimateLoaderSumsAnalyzeEntriesPerSegment`（1.47TB `/System/Volumes` 被排除）、`testSystemSegmentNeverProbesTheDataVolume` 通过；本机用捆绑 mole 实测 `/System` 子项合计约 7.5s（最大 `/System/Library` 5.28s），「秒级、不触 120s 超时」成立。
- AC-011 re_verified：`testPartialHistoricalCacheRendersFirstThenCompleteScanOverwrites` 通过（先渲染部分缓存、完整扫描覆盖，`capturedAt` 断言）。
- AC-012 re_verified：`StorageBreakdown.make`（`StorageEstimate.swift:26-53`）四段求和、负值 clamp 0；`testStorageBreakdownClampsNegativeValuesToZero` 等通过。

coverage = 11 / 12（trust_prior 1 项：AC-008，占 8%，均因本环境无法 GUI 截图；建议合并前人工抽查）

reviewed_scope: 0efd15d67741c0de

verdict: FAIL

______________________________________________________________________

## Round 2 (2026-10-17T04:59:30+08:00)

### 前轮 finding 复核

- **t036_gen_f001（important，系统段部分和落盘）— 已消除**。`StorageEstimateLoader.directoryChildren(of:)`（`StorageEstimate.swift:118-134`，按 `.isDirectoryKey` 只列目录，普通文件子项如 `/System/.localized` 不再进入探测）成为 `systemChildren` 默认实现（:90、:112）；`systemSize`（:156-171）对任一 `.filter { $0 != "Volumes" }` 后的目录子项 `guard let size = try await directorySize(...) else { return nil }`，整段返回 nil（空探测集亦 nil，:164），经 `OverviewViewModel.swift:386` 的 `guard sums.isComplete` 不落盘、不接替、下次重试。新增 `testSystemSegmentIsUnavailableWhenAnyChildProbeFails`（`OverviewCacheTests.swift:249`）断言 `sums.system == nil` 且 `isComplete == false`，独立重跑通过。与 `architecture.md:81`（同轮更新为「任一子项读取失败该段即视为不可用」）一致。
- **t036_gen_f002（minor，刷新不保证重采样）— 已消除**。新增 `StatusViewModel.resample()`（`StatusViewModel.swift:163-169`）＝ `await pause()` 后 `start()`；概览刷新按钮改为 `Task { await statusViewModel.resample() }`（`OverviewView.swift:50-52`）。代码路径：`pause()` 内 `watchService.pause() → stopProcess()` 会 join 旧进程任务后才返回，随后 `start→subscribe→start()` 时 `processTask` 已为 nil，`startProcessIfNeeded` 必然新起 mole watch 进程 → 新采样；旧订阅取消与新订阅无竞态（resample 串行等待）。`testOverviewRefreshResamplesByRestartingTheSubscription`（`OverviewTests.swift:164`）独立重跑通过（pauseCallCount ≥ 1、isSampling 复位 true）。
- **t036_gen_f003（minor，行 id 可能重复）— 已消除**。`OverviewActivityRow.make(index:symbol:session:)` id = `"activity-\(index)"`（`OverviewViewModel.swift:178-180`），`OverviewActivity.rows` 经 `enumerated()` 传入（:191-194），序号稳定、不可能重复。
- **t036_gen_f004（minor，无用 import/键/`memoryText`）— 已消除**。`OverviewViewModel.swift:1-2` 仅剩 Combine/Foundation（SwiftUI import 已删）；`overview.memory` 键已从 `Localizable.xcstrings` 删除（`rg --fixed-strings` src+tests 零命中）；`memoryText` 由四宫格复用（`OverviewViewModel.swift:157`）。
- **t036_gen_f005（minor，architecture 文档过时）— 已消除**。`architecture.md:81` 改为「用三次固定 `analyze` 加系统段逐项求和…按 `/System` 顶层目录子项逐个 `analyze` 并求和」，与代码一致；新增测试策略同步存在于 `OverviewCacheTests`。

### t036_gen_f006 - architecture.md 概览段仍描述已删除的趋势条

- 严重度：minor
- 锚点：文档一致性（本 diff 删除概览趋势条后，同节描述未同步）；无 AC 锚定
- 位置：`docs/blueprint/architecture.md:85`
- 问题：该句「最近操作复用 `history --json`。趋势只在采样点达到阈值时绘制，否则显示采样不足」描述的正是本 task 删除的概览趋势卡（anchor 期 `OverviewTrend.hasEnoughSamples` + `trendCard`）；本 diff 更新了同节 81/83 两段却漏改 85 行，读者会以为概览仍有趋势条。
- 建议：改写为「概览不再有趋势条；`status --watch` 系列仅供状态页图表使用」，或删除该句。

### 未进表的提示

- 修复引入的残余边角（不构成 finding，无现实失败场景）：`directoryChildren`（`StorageEstimate.swift:118-134`）用 `try?` 吞掉单条 `resourceValues` 失败——此时该目录子项会被静默剔出探测集而段和仍视为完整；在目录列表已成功的本地 APFS 场景无法构造该失败，提示实现方可顺手改显式 `do/catch` 置 nil。
- AC-008 视觉项：工作区仍无截图产物（`.scratch/ui_rebuild` 仅 `demo_data/`），合并前建议人工抽查。
- 同 Round 1 的范围外/既有观察继续：活动行时间显示原始 ISO 8601；`hasRecentOperations` 仅测试引用；`dataVolumeAnalyzeFixture` 为防御性夹具。
- 变更规模：15 文件 +939/−294（较 Round 1 新增 `StatusViewModel.swift` 的 `resample()`），仍属单 task 合理范围。

### AC 复验方式（本轮）

- AC-001 re_verified：刷新按钮 → `resample()`（`OverviewView.swift:50-52`、`StatusViewModel.swift:163-169`，pause+start 强制重订阅）；`testOverviewRefreshResamplesByRestartingTheSubscription` 通过；清理入口 `navigation.select(.clean)` 与 `lastReclaimBytes` 空值纯文案不变。
- AC-002 re_verified：`OverviewHealthCard.make` 占位逻辑未变；`OverviewLayoutTests` 全绿。
- AC-003 re_verified：三 tile 真实源未变（reclaim 仍取 `CleanViewModel.lastReclaimBytes`）。
- AC-004 re_verified：`OverviewStorageCard` 与不完整文案未变；相关用例通过。
- AC-005 re_verified：活动行映射未变（仅 id 改序号）；`OverviewLayoutTests` 通过。
- AC-006 re_verified：四宫格内存值改复用 `metrics.memoryText`（`OverviewViewModel.swift:157`），映射语义等价；`testStatusGridMapsRealSamplesAndPlaceholders` 通过。
- AC-007 re_verified：快捷卡/趋势类型与视图仍零命中。
- AC-008 trust_prior：同 Round 1，依赖实施侧截图自述，工作区无产物。
- AC-009 re_verified：取消路径未变（`computeEstimate` catch）；`testCancelledScanDoesNotPersistAnything` 通过。
- AC-010 re_verified：`systemSize` 现对任一目录子项失败返回 nil（`StorageEstimate.swift:166-169`），`testSystemSegmentIsUnavailableWhenAnyChildProbeFails` 与 `testSystemSegmentNeverProbesTheDataVolume` 通过；口径/秒级结论同 Round 1（本机实测子项合计约 7.5s）。
- AC-011 re_verified：`testPartialHistoricalCacheRendersFirstThenCompleteScanOverwrites` 通过。
- AC-012 re_verified：四段求和/负值 clamp 未变；相关用例通过。
- 回归证据：本轮独立重跑 `xcodebuild test -project Zmole.xcodeproj -scheme Zmole -destination 'platform=macOS'`，270 例 0 失败（含 `testSystemSegmentIsUnavailableWhenAnyChildProbeFails`、`testOverviewRefreshResamplesByRestartingTheSubscription`）。

coverage = 11 / 12（trust_prior 1 项：AC-008，占 8%，同 Round 1；建议合并前人工抽查）

### 本轮结论

- 本轮新发现：1 条（minor，t036_gen_f006）
- 总体判断：f001～f005 以当前 diff/代码与独立重跑核实均已真修（f001 系统段任一目录子项失败即整段不可用，与「不完整不落盘」不变量一致；f002 刷新经 pause+start 必然触发新采样）；本轮仅新增 1 条文档残留 minor，无未解决 critical / important，本轮 PASS。
- 系统性 follow-up：无

reviewed_scope: c66ac5f8bfc07600

verdict: PASS

______________________________________________________________________

## Round 3 (2026-10-17T05:01:27+08:00)

### 前轮 finding 复核

- **t036_gen_f006（minor，architecture.md 仍描述已删除的趋势条）— 已消除**。`architecture.md:85` 现为「最近操作复用 `history --json`。概览不再绘制趋势条；状态页的系统负载图在采样点不足时显示等待说明，不伪造趋势。」；与当前实现一致：`rg "OverviewTrend|trendCard"` 在 src 零命中，状态页等待语义由 `StatusView.swift:277-291`（`StatusChart.isDrawable` 不足时 `status.trend_waiting`）支撑；同节 81/83 两行与 Round 2 已审文本逐字一致（见下 delta 核实）。

### 本轮交付 delta 核实

- 仅 `docs/blueprint/architecture.md` 在 Round 2 之后被修改（mtime 04:59:07；其余 14 个交付文件的 mtime ≤ 04:53:16，均早于 Round 2 复核完成时刻），且该文件本轮变化仅第 85 行一句（`git diff <anchor>` 中 81/83 行内容与 Round 2 一致）；无代码、测试、配置改动。

### 本轮新发现

无（0 条）。对本轮 delta（一句 blueprint 文档）按 7 视角扫描：描述与代码一致、无规格/正确性/安全/契约/性能/架构/测试影响，未命中。

### 未进表的提示

- 同前两轮（不重复展开）：AC-008 视觉项无截图产物，合并前建议人工抽查；活动行时间显示原始 ISO 8601；`hasRecentOperations` 仅测试引用；`directoryChildren` 的 `try?` 边角。
- 变更规模：15 文件 +939/−294 与本轮前一致。

### AC 复验方式（本轮）

- 本轮 delta 仅 blueprint 文档一句，不触及任何 AC 行为路径；Round 1/Round 2 的逐条复验结论继续有效（AC-001～007、009～012 re_verified；AC-008 trust_prior，依赖实施侧截图自述）。
- 回归证据：本轮独立重跑 `xcodebuild test -project Zmole.xcodeproj -scheme Zmole -destination 'platform=macOS'`，270 例 0 失败；`git diff --check <anchor>` 退出码 0。

coverage = 11 / 12（trust_prior 1 项：AC-008，同前两轮）

### 本轮结论

- 本轮新发现：0 条
- 总体判断：f006 已消除，文档改动与其描述的实现一致，此前闭合项无回归、无新问题；无未解决 critical / important，本轮 PASS。
- 系统性 follow-up：无

reviewed_scope: a8575a3f3074ffd8

verdict: PASS
