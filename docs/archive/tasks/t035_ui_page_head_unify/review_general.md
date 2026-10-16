# Task review t035（reviewer_focus: 通用）

- task：`t035_ui_page_head_unify`
- spec：`docs/tasks/t035_ui_page_head_unify/spec.md`
- diff_anchor：`02db874621bd1484e6f5d87caa9043003455500f`
- target：`git -C '/Users/karson/kar/code/zmole_t035' diff 02db874621bd1484e6f5d87caa9043003455500f`
- round：1
- reviewed_at：2026-10-17T03:43:43+08:00

## Findings

### t035_gen_f001 - UtilityToolbar / UtilityMetric 成为死代码

- 严重度：minor
- 锚点：架构与可维护性（本 diff 删除最后调用方后未清理定义）；无 AC 锚定
- 位置：`src/zmole/Features/UtilityUI.swift:21`（`UtilityToolbar`）、`src/zmole/Features/UtilityUI.swift:242`（`UtilityMetric`）
- 问题：diff 将 AnalyzeView 的 `UtilityToolbar` 换成 `MolePageHead`（AnalyzeView.swift:44）、把 StatusView 的 3 处 `UtilityMetric` 换成 `MoleStatTile`（旧 StatusView.swift:77/83/89），但两个组件定义保留。当前 `rg -n "UtilityToolbar|UtilityMetric" src/zmole --glob '!Features/UtilityUI.swift'` 零命中；anchor 版本 `git grep` 在上述位置有命中。无行为缺陷，但违反「删除因自己修改而无用的定义」。
- 建议：删除这两个 struct（及其仅在内部使用的分支，如 `UtilityMetric.fraction`）；若确有保留理由，在 `task.md` 实施笔记写明。

### t035_gen_f002 - 本地化键残留与新增未用键

- 严重度：minor
- 锚点：文档/配置一致性（本 diff 移除了若干键的最后引用，且新增了一个从未被引用的键）；无 AC 锚定
- 位置：`src/zmole/Resources/Localizable.xcstrings:73-86,138,190,206-215,279-281,419`
- 问题：以下键在 anchor 版本被 Swift 引用（`git grep` 各命中 1 处），本 diff 删除对应 UI 后不再被任何代码引用：`status.disk_io`(73)、`status.disk_io_warming`(74)、`status.read`(75)、`status.write`(76)、`status.trend_ready`(85)、`status.unavailable`(86)、`uninstall.refresh`(138)、`status.disk`(190)、`analyze.refresh`(206)、`history.deletions`(207)、`history.items`(211)、`history.sessions`(214)、`history.size`(215)、`status.thermal`(279)、`status.zombies`(281)。另外新增的 `analyze.subtitle`(419)（文案为磁盘页浏览说明）当前零引用，而 AnalyzeView.swift:47 的副标题用的是 `analyze.read_only`。无行为缺陷，属死配置。
- 建议：删除这批残留键；`analyze.subtitle` 二选一——接入为磁盘页副标题或删除，避免新增即死键。

### t035_gen_f003 - 页头接入类测试只断言源码文本，不触达行为

- 严重度：minor
- 锚点：测试可信与覆盖（断言未触达可观察行为，且对无关改动会误报/漏报）；对应 AC-006、AC-020～AC-022 的辅助证据
- 位置：`tests/unit/UiAlignmentTests.swift:189-241`（`PageHeadAdoptionTests`）
- 问题：4 个测试全部读源文件字符串：`source.contains("MolePageHead(")`（190-205）、`!source.contains(".toolbar {")`（207-215）、键后 160 字符窗口内 `contains("isInfo: true")`（217-241）。这类断言在运行时页头未渲染（例如被包进不渲染分支）时仍会通过；反之，HistoryView 将来为与页头无关的用途加 `.toolbar {`、或参数顺序调整使 `isInfo: true` 落在 160 字符窗口外时，会误报失败。AC-006 与信息条样式的权威验证本就是截图（可测试性声明），这些测试只宜当 smoke，不能当作行为覆盖。
- 建议：保留作 source smoke 时在测试注释中声明其性质；或删除对布局结论的源码断言，行为部分维持现有 `NoticeTone` 纯逻辑测试。不要求本 task 重写。

## 结论

- 本轮新发现：3 条（均 minor，无 blocking）
- 未进表的提示：
    - 进程表第 4 列表头用 PID 取代 demo 的「运行状态」列（`StatusView.swift:208`）；现有数据源无运行状态字段，该改动不在 spec 契约内，仅记录待后续 finalization 时核对 ui_contract/demo 表述。
    - 状态页副标题 `status.subtitle` 沿用 demo 文案「每 2 秒更新」（`Localizable.xcstrings:20`），但 `StatusWatchService` 默认采样间隔 1s（`StatusWatchService.swift:83`，AppDependencies.swift:650 未覆盖）。文案与真实节奏不一致，来源为已批准的 demo 文案，未进 finding。
    - 视觉类 AC（007/014/019/024）依赖 `--demo` 截图人工核对；工作区内未见截图产物（`.scratch` 仅有 review prompt），task.md 的「截图核对」自述无法独立核验，建议合并前人工过一遍。
    - 新交付文件 `src/zmole/Features/Status/StatusChart.swift` 处于未跟踪状态且未被 `git add -N`，不出现在 `git diff`；reviewer 已直接读取全文，且其内容已计入 reviewed_scope 指纹（重算一致），不判 INCOMPLETE，仅提示流程上补齐。
    - 变更规模：15 文件 +896/−260，属单 task 合理范围；`UninstallView.swift` 457 行为既有规模，未因本 task 明显膨胀。
- 总体判断：实现与契约区 AC 对齐，五页页头/状态页指标与负载图/历史表格/信息条均按 spec 落地；独立复跑 `xcodebuild test -scheme Zmole`（257 例全过，含全部新增用例）与源码查证未发现 critical/important，仅 3 条 minor，可 PASS。
- 系统性 follow-up：无（f001/f002 属本 task 自产的清理项，建议在本 task 处置表中就地处置）

### AC 复验方式

- AC-001 re_verified：`UninstallView.swift:67-104` 页头动作按现有状态机映射 loadList/cancelList/cancelPreview/cancelExecution；卸载相关既有用例在本次全量 257 例中通过。
- AC-002 re_verified：`AnalyzeView.swift:44-59` 页头 + `analyze.back` 以 `viewModel.canGoBack` 禁用（AnalyzeViewModel.swift:70 根目录置 false）+ `analyze.rescan`。
- AC-003 re_verified：`StatusView.swift:30-49` 复用原 start/pause/retry 处理；StatusViewModel/StatusWatchService 未被本 diff 触碰；`testPopulatedDemoStatusKeepsSamplingUntilPaused` 通过。
- AC-004 re_verified：`HistoryView.swift:17-34` 导出/刷新接线；`SettingsHistoryTests.testEmptyHistoryShowsEmptyStateAndExportMatchesJSON` 通过（导出写 `rawJSON`）。
- AC-005 re_verified：`SettingsView.swift:28-40` 使用 `MolePageHead` EmptyView 初始化（UtilityUI.swift:87-91），无动作区渲染负担。
- AC-006 re_verified：`rg '\.toolbar'` 在五页文件零命中；残留 toolbar 仅属非范围页（Optimize/Purge/Whitelist/AppShell 命令面板）。
- AC-007 trust_prior：视觉布局/三语/窗口宽度需 GUI 截图，工作区无截图产物，依赖实施侧 task.md「黑盒截图」自述。
- AC-008 re_verified：`StatusStatValues.make`（StatusChart.swift:77-99）四格取值与占位，`StatusStatValuesTests` 3 例通过（含 warming 不显示 0）。
- AC-009 re_verified：`StatusChart.windowed(60)` 裁剪 + 视图取 `cpuUsage`/`memoryUsedPercent` 两序列；`StatusChartTests` 5 例通过。
- AC-010 re_verified：`isDrawable` 需 ≥2 点，否则显示 `status.trend_waiting`（StatusView.swift:277,290-294）；不足两点不出线的测试通过。
- AC-011 re_verified：`StatusView.swift:151-171` 下载/上传 metricLine；`networkTotal == nil`（首帧）显示 `status.sampling`。
- AC-012 re_verified：进程区无结束动作；`processStale` 徽标保留（StatusView.swift:184）；僵尸徽标只读。
- AC-013 re_verified：暂停/恢复/离页停止代码路径未变（StatusViewModel/StatusWatchService/AppShellView 未进 diff），相关用例通过。
- AC-014 trust_prior：图表浅深色与窗口裁切为视觉项，需截图人工核对。
- AC-015 re_verified：`HistoryView.swift:113-125` 四列表头与固定列宽；`HistoryTableTests` 3 例通过。
- AC-016 re_verified：`HistoryTable.rows` 生成 session+deletion 行，deletion 行 action 显示完整路径（HistoryView.swift:168-175）；测试断言两类行均在场。
- AC-017 re_verified：`rows.isEmpty` 走空状态（HistoryView.swift:89-100）；空态在 `SettingsHistoryTests` 与 `HistoryTableTests` 通过。
- AC-018 re_verified：`HistoryViewModel.export` 未改动，导出内容与 `history --json` 原文相等的断言通过。
- AC-019 trust_prior：三语/1100×700 表格可读性为视觉项，需截图核对。
- AC-020 re_verified：`OptimizeView.swift:65` isInfo:true；token 值 `#EAF1FF`/`#355B99` 与 demo `--blue-soft`/`.info-banner` 色值一致；`NoticeToneTests` 通过（最终渲染外观仍属视觉项）。
- AC-021 re_verified：`PurgeView.swift:65` 同款接线与 token。
- AC-022 re_verified：`HistoryView.swift:48` shield 图标 + info 样式；文案与 demo info-banner 一致。
- AC-023 re_verified：`UtilityNotice` error 分支颜色/语义与旧实现逐行一致（UtilityUI.swift:181-195）；`PageHeadAdoptionTests` 断言 permanent_note 仍 isError 并通过。
- AC-024 trust_prior：浅深色文字对比度与三语溢出为视觉项，需截图核对。

coverage = 20 / 24（trust_prior 4 项：AC-007/014/019/024，占 17%，均因无法在本环境启动 GUI 截图）

reviewed_scope: c21ad67238e51e73

verdict: PASS

______________________________________________________________________

## Round 2 (2026-10-17T03:54:29+08:00)

### 前轮 finding 复核

- **t035_gen_f001（minor，死代码）— 已消除**。`UtilityUI.swift` 中 `UtilityToolbar` 与 `UtilityMetric` 两个 struct 定义已随本轮修复删除（`git diff 02db8746...` 中 `-struct UtilityToolbar` / `-struct UtilityMetric` 可见，文件以 `UtilityBadge` 收尾）；`rg -n "UtilityToolbar|UtilityMetric" src tests` 零命中；独立重跑 257 例测试通过。
- **t035_gen_f002（minor，本地化残留）— 修不彻底**。已删除 25 键（含 `analyze.subtitle` 与 16 个 anchor 期即已死键）；逐键核实「删除的键现在零引用，且不涉及唯一的动态键构造 `sidebar.\(rawValue)`」（`AppDestination.swift:40,42`），删除安全；现存全部键三语完整、JSON 合法，共享键值唯一变更仍是 Round 1 已审的 `status.subtitle`。但 Round 1 明确列出的下列 7 键仍在目录且引用为 0（`rg --fixed-strings` 带引号精确匹配 src+tests 全为 0）：`status.trend_ready`（`Localizable.xcstrings:75`）、`uninstall.refresh`（:127）、`analyze.refresh`（:185）、`history.deletions`（:186）、`history.items`（:190）、`history.sessions`（:193）、`history.size`（:194）。请补删，或处置表改标「遗留」并指向 follow-up。
- **t035_gen_f003（minor，源码断言测试）— 同意撤回**。「仓库既有同类先例」独立核实成立：`tests/unit/CleanPageTests.swift:166-172` 对 `CleanView.swift` 做 `XCTAssertFalse(source.contains(forbidden))` 的源码禁令断言、`tests/unit/OptimizeTests.swift:28-33` 断言 `OptimizeView.swift` 含 `"ScrollView"`；该模式确为仓库既有惯例、非本 task 新引入，且 Round 1 已注明不要求本 task 重写。撤回成立，不再强制改代码。

### t035_gen_f004 - 旧本地化键测试被就地改键，未按规则整体删除或改名

- 严重度：minor
- 锚点：AGENTS.md「TDD」规则——实现变更使旧测试语义失效时，旧测试须原样保留或整体删除并写明理由，禁止就地把旧测试的预期改成当前实现的输出；无 AC 锚定
- 位置：`tests/unit/ZmoleTests.swift:95-116`
- 问题：f002 清理删除了 `status.health_detail` / `status.cpu.detail` / `status.memory.detail`（删除前 src 引用为 0、仅被该测试引用），实现侧将测试内 key 列表就地替换为 `status.stat.*` 四键（本轮 diff 仅 5 行 hunk + 注释）。缓解事实：断言强度未削弱（3 键→4 键、同 3 locale、同「非空且 ≠key」断言），注释说明了替换原因，无掩盖回归迹象；遗留瑕疵：测试名 `testStatusMetricDetailKeysHaveLocalizedValues` 与新断言对象（指标条标签）已不符。
- 建议：最小修复改名为 `testStatusStatKeysHaveLocalizedValues`；或按规则整体删除旧测试、在实施笔记写明理由后新增新测试。

### 未进表的提示

- f002 的 7 个残留键属本 task 自产死配置：建议就地补删，或在处置表标「遗留」指向 follow-up；不构成阻断。
- 范围外观察（anchor 期即存在、非本 task 引入）：`clean.error.failed` 在 `CleanViewModel.swift:142,258` 用作 `errorKey`，经 `CleanView.swift:264-266` 以 `LocalizedStringKey` 渲染，但该键在 anchor 与当前 catalog 中均缺失，会显示原始键名；CleanView/CleanViewModel 不在本 diff，仅提示。
- `src/zmole/Features/Status/StatusChart.swift` 仍未 `git add -N`（未跟踪但可读；内容与 Round 1 一致、已计入指纹），不判 INCOMPLETE，提示流程补齐。
- 视觉类 AC 的截图产物仍未见于工作区（同 Round 1），合并前建议人工抽查。

### AC 复验方式（本轮）

- 本轮 delta 仅四处：`UtilityUI.swift`（删死代码）、`Localizable.xcstrings`（删零引用键）、`tests/unit/ZmoleTests.swift`（测试键列表替换）、`task.md`（流程文件）；逐键核实被删键引用为 0，未触及任何 AC 行为路径，Round 1 的逐条复验结论（AC-001～006、008～013、015～018、020～023 re_verified；AC-007/014/019/024 trust_prior，依赖人工截图）继续有效。
- 回归证据：本轮独立重跑 `xcodebuild test -scheme Zmole -destination 'platform=macOS'`，257 例 0 失败（含更新后的 `testStatusMetricDetailKeysHaveLocalizedValues` 与全部新增用例）。

coverage = 20 / 24（与 Round 1 相同：re_verified 20、trust_prior 4，均为 GUI 截图项）

### 本轮结论

- 本轮新发现：1 条（minor，t035_gen_f004）
- 总体判断：f001 已消除、f002 修不彻底（7 键残留）、f003 撤回成立；新发现 1 条 minor。无未解决 critical / important，本轮 PASS。
- 系统性 follow-up：无（f002 残留建议本 task 就地补删）

reviewed_scope: 151999ca9904acbe

verdict: PASS

______________________________________________________________________

## Round 3 (2026-10-17T03:59:44+08:00)

### 前轮 finding 复核

- **t035_gen_f004（minor，旧测试就地改键）— 已消除**。`tests/unit/ZmoleTests.swift:95-119`：测试改名为 `testStatusStatKeysHaveLocalizedValues`（第 99 行），注释显式写明与旧 `testStatusMetricDetailKeysHaveLocalizedValues` 的替换关系及「三语指标标签」同一意图；断言体未变（`status.stat.*` 四键 × en/zh-Hans/zh-Hant，仍断言非空且 ≠key），断言强度未削弱；旧测试名在 src/tests 中已无残留；独立重跑中该用例通过（`tests/unit/ZmoleTests.swift:99`）。
- **t035_gen_f002 收尾复核（Round 2 判「修不彻底」）— 已消除**。7 个残留键（`status.trend_ready`、`uninstall.refresh`、`analyze.refresh`、`history.deletions`、`history.items`、`history.sessions`、`history.size`）已从 catalog 删除；逐键核对 src+tests 引用为 0；removed-vs-anchor 由 24 → 31、added 保持 32，无意外改动；catalog 三语完整、JSON 合法；共享键值变更仍仅 `status.subtitle`（Round 1 已审）。
- **已闭合项无回归**：`UtilityUI.swift`（f001）与 `tests/unit/UiAlignmentTests.swift`（f003 撤回项）本轮均无改动（diff --stat 与 Round 2 一致）；五页源码 `.toolbar` 零命中状态未变。

### 本轮新发现

无（0 条）。对本轮 delta（`Localizable.xcstrings` 删 7 键、`ZmoleTests.swift` 改名、`task.md`）按 7 视角（规格/正确性/安全/契约·Breaking/性能·资源/架构·可维护性/健壮性·可观测/测试·文档·配置）扫描：删除键零引用（无运行时缺键风险）、测试断言未削弱、无范围外新增改动，均未命中。

### 未进表的提示

- 同 Round 2：范围外 `clean.error.failed` 缺键仍存在（anchor 期即存在，`CleanViewModel.swift:142,258` 经 `CleanView.swift:264-266` 渲染）；`src/zmole/Features/Status/StatusChart.swift` 仍未 `git add -N`（已读取、已计入指纹，不判 INCOMPLETE）；视觉类 AC 截图产物仍未见于工作区，合并前建议人工抽查。
- 处置表中 f002/f004 标「已修」与本轮独立核实一致；f001/f003 无回归。

### AC 复验方式（本轮）

- 本轮 delta 仅 `Localizable.xcstrings`（删 7 个零引用键）、`tests/unit/ZmoleTests.swift`（改名 + 注释）、`task.md`（流程文件）；逐键核实删除键引用为 0、新增/共享键不变，未触及任何 AC 行为路径，Round 1 的逐条复验结论（AC-001～006、008～013、015～018、020～023 re_verified；AC-007/014/019/024 trust_prior，依赖人工截图）继续有效。
- 回归证据：本轮独立重跑 `xcodebuild test -scheme Zmole -destination 'platform=macOS'`，257 例 0 失败（含改名后的 `testStatusStatKeysHaveLocalizedValues` 与全部新增用例）。

coverage = 20 / 24（与 Round 1/2 相同：re_verified 20、trust_prior 4，均为 GUI 截图项）

### 本轮结论

- 本轮新发现：0 条
- 总体判断：f004 已消除、f002 残留已补清，此前闭合项无回归，无新问题；无未解决 critical / important，本轮 PASS。
- 系统性 follow-up：无

reviewed_scope: ab1c1ac69afaccc5

verdict: PASS

---

## Round 4 (2026-10-17T04:05:50+08:00)

### 前轮 finding 复核

- Round 3 为 0 新发现的 clean 轮，`t035_gen_f001`～`f004` 已全部闭合（已消除 / 同意撤回）。本轮对当前 tip（执行 commit `51f2c7eaacdb`，worktree 干净）的完整交付内容重新核验。
- **Round 3 → 当前 tip 的交付 delta 经哈希级证明仅为 `UtilityUI.swift` 的 EOF 空行修正**：当前 blob `git hash-object src/zmole/Features/UtilityUI.swift` = `a702eb4795609f25da9cb20eec673add9e57fbeb`，与 `51f2c7e:src/zmole/Features/UtilityUI.swift` 一致；对该 blob 追加一个 `\n` 后哈希 = `d2cd8fb0bd538735ec8ff7b20391da830fe95b1a`，恰等于 Round 2/3 已审版本的 blob hash（`d2cd8fb`），故唯一差异为删除文件末尾多余空行，无任何逻辑变化。
- **其余交付文件与 Round 3 逐字节一致（可核部分）**：`src/zmole/Features/Status/StatusChart.swift` sha256 = `f2d36248fc82c6d3f9ba3fc7ed4e8865314d2692bd360c640a712ca73bf9b844`，与 Round 3 记录相同；全部交付文件 `git diff --stat` 与 Round 3 完全一致（唯一变化是 `UtilityUI.swift` 160→161 的变更计数，对应本次 EOF 修正）。
- **此前闭合项无回归**：`rg "UtilityToolbar|UtilityMetric" src tests` 零命中（f001）；7 个残留键（`status.trend_ready`、`uninstall.refresh`、`analyze.refresh`、`history.deletions`、`history.items`、`history.sessions`、`history.size`）在 `Localizable.xcstrings` 中均不存在（f002）；`tests/unit/ZmoleTests.swift` 测试名 `testStatusStatKeysHaveLocalizedValues` 未变且运行通过（f004）；`UiAlignmentTests.swift` 无改动（f003 撤回项）。
- **EOF 修复验证**：`git show --check 51f2c7eaacdb` 无空白告警；`git diff --check 02db874621bd1484e6f5d87caa9043003455500f` 退出码 0，原 `git diff --check` 的 EOF 空行问题已清除。
- 归档迁移（`task.md` / `review_general.md` / `handoff.json` 入 `docs/archive/tasks/t035_ui_page_head_unify/`、`spec.md` 同树移动 0 变更）属流程文件与附件迁移，按指纹规则排除于审查范围；`handoff.json` 记录的 base_sha/测试/ review 结论与本次独立核实一致。

### 本轮新发现

无（0 条）。本轮实际 delta 仅「UtilityUI.swift EOF 空行删除 + 流程文件归档迁移」，按 7 视角（规格/正确性/安全/契约·Breaking/性能·资源/架构·可维护性/健壮性·可观测/测试·文档·配置）逐项扫描：无逻辑变更、无新增文件、无范围外改动、无引用/缺键/断言问题，均未命中。

### 未进表的提示

- 同前轮：范围外 `clean.error.failed` 缺键（anchor 期即存在，`CleanViewModel.swift:142,258` 经 `CleanView.swift:264-266` 渲染）仍待 follow-up；视觉类 AC（007/014/019/024）依赖人工截图，`handoff.json` 记录 demo 截图已完成但工作区无产物可独立核验。
- 本轮报告将随补审证据 amend 入 `51f2c7eaacdb`；此后任何交付内容改动都会使本 PASS 与 `reviewed_scope` 失效。

### AC 复验方式（本轮）

- 本轮交付内容相对 Round 3 仅 EOF 空白一处（哈希级证明），未触及任何 AC 行为路径，Round 1 的逐条复验结论（AC-001～006、008～013、015～018、020～023 re_verified；AC-007/014/019/024 trust_prior，依赖人工截图）继续有效。
- 回归证据：本轮独立重跑 `xcodebuild test -scheme Zmole -destination 'platform=macOS'`，257 例 0 失败（含 `testStatusStatKeysHaveLocalizedValues`、`PageHeadAdoptionTests`、`StatusChartTests`）。

coverage = 20 / 24（与 Round 1～3 相同：re_verified 20、trust_prior 4，均为 GUI 截图项）

### 本轮结论

- 本轮新发现：0 条
- 总体判断：当前 tip 交付内容与此前已 PASS 的版本逐字节一致（除经哈希证明的 EOF 空行修正），此前闭合项无回归、无新问题；无未解决 critical / important，本轮 PASS。
- 系统性 follow-up：无

reviewed_scope: d5906716f44a57e4

verdict: PASS
