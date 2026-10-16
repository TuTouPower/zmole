# Task review t028（reviewer_focus: 代码）

- task：`t028_disk_incremental_scan`
- spec：`docs/tasks/t028_disk_incremental_scan/spec.md`
- diff_anchor：`3d42958b84fbfc08d96a24d20b3a8613ee31f3a6`
- target：`git -C '/Users/karson/kar/code/zmole_t028' diff 3d42958b84fbfc08d96a24d20b3a8613ee31f3a6`
- round：1
- reviewed_at：2026-10-17T01:30:01+08:00

reviewed_scope: 9e3527df4325335b

审查范围完整性：`git status --porcelain` 无未跟踪交付文件；新增文件 `src/zmole/Features/Analyze/DiskScanner.swift`、`tests/unit/DiskScannerTests.swift` 已 `git add -N` 出现在 diff 中；HEAD 等于 diff_anchor，交付内容即未提交改动。已独立重跑 `xcodebuild test -scheme Zmole -destination 'platform=macOS'`（208 tests, 0 failures）。

## Findings

### t028_code_f001 - 子路径拼接逻辑三处重复实现

- 严重度：minor
- 锚点：DRY（代码质量；无对应 AC，行为无分叉）
- 位置：`src/zmole/Features/Analyze/DiskScanner.swift:150`（`LiveDiskScanner.childPath`）、`src/zmole/App/AppDependencies.swift:340`（`DemoDiskScanner.child`）、`src/zmole/Features/Analyze/AnalyzeViewModel.swift:221`（`invalidateSubtree` 内联 `path.hasSuffix("/") ? path : path + "/"`）
- 问题：同一「父路径 + 名称/前缀」拼接规则在 scanner、demo fixture 与 ViewModel 三处 verbatim 重复。当前三份实现一致，无行为分叉；属纯重复，后续若改路径规则（如尾斜杠处理）需同步三处。
- 建议：`DemoDiskScanner` 与 ViewModel 复用 `LiveDiskScanner.childPath`（internal static，可直接访问），或抽一个小的路径工具；不改行为。

### t028_code_f002 - 缓存层级的合计口径与自身行不一致（硬链接去重按祖先上下文）

- 严重度：minor
- 锚点：AC-003（当前层合计等于已计入条目的字节和）与 AC-009（同一扫描内硬链接只计一次）的口径冲突；spec 风险区已预告「父目录总量取法需实现时确认」
- 位置：`src/zmole/Features/Analyze/DiskScanner.swift:229-246`（walk 全局去重、行仍显示自身字节）、`src/zmole/Features/Analyze/AnalyzeViewModel.swift:191-199`（子目录值取 `result.totalSize`）、`:203-211`（walk 层级直接作为缓存记录，合计沿用祖父上下文去重值）
- 问题：被去重的层级其缓存合计可能小于自身行之和，甚至为 0。可复现场景：`/root` 有直接文件 `a.bin`（分配块 4096），并有目录 `sub`；`sub` 内有 `b.bin`，是 `a.bin` 的硬链接。扫描 `/root` 时 listing 先计入 `a.bin`，随后测量 `sub` 时 `b.bin` 已被去重 → `sub` 的 walk 合计为 0，但 `b.bin` 行仍显示 4 KB。结果：`/root` 行中 `sub` 显示 0 字节；进入缓存里的 `sub` 时「当前层合计 = 0 字节」而行内有 4 KB 文件，百分比列显示「—」。若用户先进入 `sub`（新去重器，合计 4096）再返回，同一目录会出现两个合计值，取决于进入时序。非崩溃/数据问题，且当前行为可辩护为「同一扫描全局只计一次」的实现选择，但与 AC-003 的按层字面读法不符，且「大小已知后合计」在硬链接场景下会小于行和。
- 建议：二选一并记录：a) `walk` 为每层同时返回「层内自身去重合计」，缓存记录的显示合计用它，父合计仍用跨层去重值（进入缓存目录与单独列举结果一致）；b) 维持现状为产品口径，在 spec/task.md 明确「硬链接按扫描全局去重，缓存层合计可能为 0，百分比显示 —」，避免后续误判 bug。

## 结论

- 前轮 finding 复核：Round 1，无前轮 finding。
- 本轮新发现：2 条（均 minor，不阻断）。
- 未进表的提示：
    - 文件过大：`src/zmole/App/AppDependencies.swift` 574 行（本 task 净增 +134，≥400 实现源码阈值，按降级规则仅提示）；内含 130 行 `DemoDiskScanner` fixture，后续可拆到独立文件。其余 diff 触及文件均未超阈值（`AnalyzeView.swift` 396 行、`DiskExplorerTests.swift` 450 行接近但不越线）。
    - 圈复杂度：`LiveDiskScanner.walk`（`DiskScanner.swift:192`）手算近似 CC≈10，达结论提示线（未达 15，无 finding）；`AnalyzeViewModel.apply` 与 `AnalyzeListOrder.sorted(.size)` ≈9，未达线。
    - 范围外观察：`DemoDiskScanner.levels` 根节点 `total: 77_953_051_392` 与其 entries 之和 78,054,295,392 不一致（`AppDependencies.swift:376-387`）；VM 只测量子目录、从不测量根，字段未被使用，无可见影响，属 fixture 潜在坑。
    - 行为观察：listing 进行中 `goBack`/`open` 被忽略（`AnalyzeViewModel.swift:70-93` guard，测试 `testBackIsIgnoredWhileListing` 固化），期间保留上一目录名单可见；测量期间导航不受限，与 AC-006 主语义一致，listing 被设计为即时返回。
- 七视角扫描确认：安全（只读 lstat/列举，无外部输入拼接执行、无 secret/日志泄漏）、契约·Breaking（无公开 API/CLI/配置键变更，`MoleCommandLanes` 删 analyze 通道为 AC-012 所需，函数签名变化均在应用内部）、性能·资源（无循环内查库、测量串行符合 spec「逐个补上」、scan 在 detached task）、架构·可维护性、健壮性·可观测（无空 catch；`DiskScanError`/`errorMessage` 路径一致，错误串风格与 `MoleBridgeError` 一致）、文档·规格（blueprint/design/task.md 与实现同步）均未命中 blocking。
- 总体判断：AC 全部有实现对应，交付范围与 spec 一致，无 critical/important；两条 minor 可选处理，可 PASS。
- 系统性 follow-up：无（f002 属本 task 内口径确认，非跨 task 缺口）。

### AC 复验方式

- AC-001–AC-007（增量扫描状态机）：re_verified — 独立重跑 `xcodebuild test`（208 tests, 0 failures），核对 `DiskExplorerTests` 对应用例与 `AnalyzeViewModel.swift:111-218` 实现（先 publish 名单、后台逐项测量、缓存直接 publish、refresh 失效子树、导航不被测量阻塞）。
- AC-008、AC-009、AC-010、AC-011、AC-014（扫描口径）：re_verified — `DiskScannerTests` 用真实临时目录断言 `st_blocks × 512`、符号链接只计自身、硬链接只计一次、不可读目录标未扫描不计入、跨设备排除；重跑通过，并核对 `DiskScanner.swift:166-251`。
- AC-012：re_verified — `MoleCommandLanes` 已无 analyze 通道（9→8），磁盘页三文件 grep 无 `MoleBridge`/`Process`/`"analyze"`；测试 `testDiskSourcesDoNotRunMoleCommands` 通过；概览估算仍走 `lanes.estimate`。
- AC-013：re_verified — 源码扫描无 delete/trash/removeItem 类控件，测试 `testDiskPageHasNoDeleteControl` 通过。
- AC-015、AC-016、AC-017：re_verified（视图层断言，spec 认可的替代验证）— `DragGesture`→`DiskSplitLayout.resized`、行与地图方块 `onTapGesture(count: 2)`、行内无「进入目录」按钮，钳位纯函数测试通过；真实鼠标手势未执行（spec「可测试性声明」豁免）。
- AC-018、AC-019：re_verified — `AnalyzeArea.share`/`barFraction` 纯函数及边界测试通过，UI 用同快照 `level.totalSize` 计算百分比、柱形条宽度成比例。

coverage = 19/19（trust_prior 0；AC-015/016/017 的真实手势按 spec 以视图层断言替代，未做人工拖动/双击抽查）。

verdict: PASS

## Round 2 (2026-10-17T01:39:12+08:00)

- 复核范围：`git -C '/Users/karson/kar/code/zmole_t028' diff 3d42958b84fbfc08d96a24d20b3a8613ee31f3a6` 与 Round 1 diff 逐 hunk 比对，本轮改动仅限下述修复与测试侧更新；`git status --porcelain` 无新增未跟踪交付文件（`review_test.md` 为测试 reviewer 报告）；重跑 `xcodebuild test -scheme Zmole -destination 'platform=macOS'` 全绿（212 tests, 0 failures）。

reviewed_scope: 70d19f4c797abae5

- 前轮 finding 复核（以 diff/代码为准）：
    - `t028_code_f001`（minor）：已消除。`DiskScanner.swift:150-157` 保留唯一 `childPath` 并新增 `directoryPrefix`；`AnalyzeViewModel.swift:221`、`AppDependencies.swift:335` 改用 `LiveDiskScanner.directoryPrefix`；`AppDependencies.swift:341-343` 的 `DemoDiskScanner.child` 改为委托 `LiveDiskScanner.childPath`。`rg 'hasSuffix\("/"\)' src/` 仅剩 DiskScanner.swift 两处定义（测试 helper 一处属测试层，不在本报告范围）。
    - `t028_code_f002`（minor）：已消除（按建议 b）。`docs/blueprint/architecture.md` 磁盘页段落已写明「同一扫描内指向同一文件的硬链接只计一次（行仍显示自身分配块，父扫描已计入的文件其子目录层合计不再重复计入）」，与 `DiskScanner.swift:229-246` 及 `AnalyzeViewModel.swift:191-211` 实现一致。附注：缓存层合计为 0、百分比显示「—」的具体呈现未逐字写入文档，属该口径隐含结果，不另立 finding。
    - Round 1 结论段「范围外观察」项（demo 根 `total` 与 entries 之和不一致）：已消除。`AppDependencies.swift:387` 修正为 `78_054_295_392`，等于 entries 之和（34,000,000,000+18,123,968,512+12,900,270,080+5,800,038,400+4,200,000,000+2,100,000,000+930,000,000+18,304+96）。
- 本轮新发现：0 条。三项修复均为恒等替换（helper 提取）与文档/fixture 数值：`directoryPrefix("/")` 仍为 `"/"`，`childPath` 语义不变；demo 根 total 无消费点（VM 只测量子目录）。新增测试（面包屑回跳、listing 失败返回、reveal 转发、名称排序、装配断言）随全套通过，未见 mock 误用/弱化断言类 inline anti-pattern。
- 未进表的提示：
    - 文件过大：`src/zmole/App/AppDependencies.swift` 574 行（本 task 净增 +134，≥400）提示维持；`tests/unit/DiskExplorerTests.swift` 571 行（测试阈值 600，未越线）。
    - 圈复杂度：`LiveDiskScanner.walk` CC≈10 提示维持；本轮未新增分支。
- 七视角扫描：改动面仅为 helper 提取、blueprint 文案与 demo fixture 数值，安全/正确性/契约·Breaking/性能·资源/架构·可维护性/健壮性·可观测/文档·规格复查均未命中。
- AC 复验方式（Round 2 增量）：重跑 212 tests / 0 failures；本轮变动涉及的 AC-004/005（helper 恒等替换）、AC-009（口径 b 文档化）、AC-012（装配点断言新增且通过）re_verified；其余 AC 复验结论与 Round 1 相同。coverage = 19/19（trust_prior 0）。
- 总体判断：两条前轮 minor 均已真修且未引入新问题，无未解决 critical/important。
- 系统性 follow-up：无。

verdict: PASS
