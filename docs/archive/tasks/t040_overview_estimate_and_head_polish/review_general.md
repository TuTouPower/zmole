# Task review t040（reviewer_focus: 通用）

- task：`t040_overview_estimate_and_head_polish`
- spec：`docs/tasks/t040_overview_estimate_and_head_polish/spec.md`
- diff_anchor：`c4a338897084ae66378113b0e88061f9c4f3e397`
- target：`git -C '/Users/karson/kar/code/zmole_t040' diff c4a338897084ae66378113b0e88061f9c4f3e397`
- round：1
- reviewed_at：2026-10-17T13:40:00+08:00

## Findings

### t040_gen_f001 - 部分段估算屏蔽失效信号/TTL 的全量重算，陈旧分段被当作权威值持续展示并落盘

- 严重度：important
- 锚点：`docs/specs/overview.md:13-14`「写入失效信号与缓存过期触发全量重算」与 `docs/blueprint/architecture.md:84`「缓存超过 TTL（6 小时）或收到写入失效信号时全量重算并回写」（本 diff 自己更新的口径）；行为缺陷：写操作后已解析分段保持写入前的旧值并被当作权威估算展示/落盘。
- 位置：`src/zmole/Features/Overview/OverviewViewModel.swift:418-419`（`partial = (sums?.isComplete == false) ? sums : nil`）、`:344-351`（触发判定）；对比 `StorageEstimate.swift:163-166`（fill-only 实现）
- 问题：`runEstimate` 只按 `sums?.isComplete` 决定是否复用已有段，完全不消费 `estimateInvalidated` 与缓存过期状态（`estimateNeedsRefresh:346` 虽然返回 true，但进入扫描后仍走 fill-only）。可复现失败场景：某次扫描 `/Users` 探测超时 → `sums = {applications, system, developer}` 已解析、`users == nil`；用户执行一次清理（`coordinator` 置 `estimateInvalidated`，`invalidationCount+1`）→ `startEstimate` 触发的扫描只重探 `/Users`（`probePaths` 排除已解析三项，`StorageEstimate.swift:163-166`），`/Applications`、`/System`、`~/Library/Developer` 沿用清理前的旧值，并以 `capturedAt = now()` 写回缓存（`OverviewViewModel.swift:422-428`）；若 `/Users` 长期失败，每次启动都重复该路径，旧分段值可无限期停留在写入前状态且时间戳不断刷新。TTL 过期对部分缓存同样只补缺失段，与「全量重算」不符。
- 建议：`runEstimate` 在 `estimateInvalidated == true` 或 `cacheEntry` 已过期时忽略 `partial`（全量重扫）；或至少保存/重试时不为复用段刷新 `capturedAt`。若确认「部分估算下复用已解析段」是有意语义，须改写 `overview.md`/`architecture.md` 的「全量重算」表述并补断言该语义的测试。

### t040_gen_f002 - 扫描启动串行排在 history 命令之后，进入概览并非「即」发起扫描

- 严重度：minor
- 锚点：AC-001「进入概览即发起目录扫描」
- 位置：`src/zmole/Features/Overview/OverviewView.swift:45-53`（`await viewModel.refreshHistory()` 之后才 `primeEstimate`/`startEstimate`）；`src/zmole/App/AppDependencies.swift:687`（history 通道超时 120s）
- 问题：历史记录加载与估算扫描是两条独立通道，但 `.task` 串行等待 `refreshHistory()` 完成后才启动估算。history 命令慢或挂起（最长到其 120s 超时）时，目录扫描启动被同步推迟，与「进入概览即发起」不符；原 p013 的问题类别正是估算被无关等待拖住。测试只覆盖 ViewModel 层，view 层顺序无断言。
- 建议：在 `.task` 中先 `primeEstimate`/`startEstimate` 再 `await refreshHistory()`，或用两个并发分支。

### t040_gen_f003 - incompleteRetryTask 与后续扫描状态机错位：可退化为全量重扫，也可能被吞掉导致无自动补扫

- 严重度：minor
- 锚点：范围「不完整时安排一次延迟自动重试（重试只探测缺失段）」；风险表「重试只探测缺失段，且每次扫描只安排一次后续重试」
- 位置：`src/zmole/Features/Overview/OverviewViewModel.swift:444-453`（补扫任务）、`:418-419`（partial 选择）、`:433`（调度点）
- 问题：(a) 部分扫描（如 `/System` 失败）调度 60s 后补扫；若期间另有触发扫描完成了全部段，补扫醒来时 `sums.isComplete == true` → `partial = nil` → `loadSums` 对四个路径做一次全量探测（`/Users` 分钟级 I/O），违背「重试只探测缺失段」。(b) 新扫描 B 在补扫 R 挂起时启动：`scheduleIncompleteRetryIfNeeded` 因 `incompleteRetryTask != nil` 不为 B 排补扫（`:445`）；R 在 B 运行中醒来 → `runEstimate` 因 `isEstimating` 直接返回（`:411`），且 `incompleteRetryTask` 已被置 nil（`:451`）；B 部分完成后既无 pending 补扫也不会重排，须等下一次触发，与「不完整时安排一次延迟自动重试」不符。
- 建议：补扫醒来先判 `sums?.isComplete == false` 才执行；在 `runEstimate` 成功路径统一重排（当前仍不完整且无 pending 时），或启动新扫描时取消并清空 pending 补扫。

### t040_gen_f004 - AC-007 无任何自动化断言覆盖 600s 超时接线

- 严重度：minor
- 锚点：AC-007「估算通道单条命令超时为 600 秒」；spec 可测试性声明「AC-001–AC-007 全部可自动测试」
- 位置：`src/zmole/App/AppDependencies.swift:699`（`timeout: 600`）；`tests/unit/OverviewCacheTests.swift`（全文件无 timeout/600 相关断言）
- 问题：600s 常量只能靠代码审阅确认；测试仅在 loader 层注入 nil 覆盖「占位+重试」，没有任何断言触达「600s 超时 → 该段 nil → 占位」链路的接线。AC-007 是 9 条 AC 中唯一零自动化断言的条目，与可测试性声明不一致。
- 建议：补一条源码断言（读取 `AppDependencies.swift` 断言估算通道 `timeout: 600`）或将 timeout 参数化后注入断言；否则修正 spec 测试策略为 `trust_prior`。

### t040_gen_f005 - AC-005 用例未真正模拟「启动者被取消」，断言区分力不足

- 严重度：minor
- 锚点：AC-005「扫描进行中离开概览再返回，不取消扫描」的测试可信度
- 位置：`tests/unit/OverviewCacheTests.swift:393-398`（`await caller.value` 后才 `caller.cancel()`，对已完成任务 cancel 是 no-op）、`:490-495`（`ScanGate.waitUntilPaused` 超时 5s 后静默返回，无 `XCTFail`）
- 问题：用例实际只证明「扫描在启动者正常结束后仍运行」；由于 caller 先完成再被取消，它无法区分「取消视图任务不会取消扫描」——若实现被改成随启动者取消（例如在 runEstimate 中检查调用者取消状态），该用例仍会通过。另 `waitUntilPaused` 超时静默返回、`release()` 在未暂停时无操作，扫描未真正暂停时用例也可能通过。
- 建议：在 caller 仍挂起时（或预先取消启动任务后）再调用 `startEstimate` 并断言扫描继续；`waitUntilPaused` 超时改为 `XCTFail`。

## 结论

- 本轮新发现：5 条（1 important / 4 minor）
- 未进表的提示：
    - AC-009 真实渲染无截图产物入库（工作区 `.scratch/`、任务目录均无本 task 截图）。按卡片理想布局核算：storage 卡在 incomplete 态内容高度约 284pt（固定 264pt，底 padding 20pt 被溢出吞掉，最后一行图例贴卡片下沿）；activity 卡满载 4 行约 266pt 亦贴边。VStack 溢出无 clip、14pt 行距大于溢出量，未达「裁切/遮挡」判定，但建议合并前用 demo 截图核对 1200×780 与 1100×700。
    - `docs/design/*.html` 参考 demo 仍含 `.eyebrow`（设计参考物料，非界面文案，不在 AC-008 范围）。
    - `MolePageHead` 去掉 `eyebrow` 参数属内部组件签名变更，全部 9 处调用点已同步，无外部破坏性影响。
    - 变更规模：25 文件 +321/−183（含 7 个文档），单 task 合理；`OverviewViewModel.swift` 455 行、`OverviewView.swift` 432 行未超阈值。
    - blueprint/spec/design 文档已在实现期同步更新（spec 上下文区要求 finalization 更新），finalization 时复核即可。
- 总体判断：估算与页头改造主体符合契约（独立重跑 275 例单测全绿，AC-001–AC-006、AC-008 复验通过），但 f001 使写失效/TTL 触发在部分估算下退化为「只补缺失段」，陈旧分段被当作权威展示并落盘、`capturedAt` 续命，属未解决 important，本轮 FAIL。
- 系统性 follow-up：无（f001/f003 建议本 task 内修复；f004 若判定接受代码审阅则改 spec 测试策略）。

### AC 复验方式

- AC-001 re_verified：`testEstimateRunsWithoutUsedBytesAndOtherSegmentArrivesLater` 独立重跑通过（usedBytes=nil 起扫，应用/系统段照常）；「即发起」的 history 串行缺口见 f002。
- AC-002 re_verified：同用例断言 usedBytes 迟到后 `otherBytes == 500-(40+25+30+60)` 且扫描次数不增；代码 `usedBytesDidChange`（`OverviewViewModel.swift:374-383`）。
- AC-003 re_verified：`testIncompleteScanRendersPersistsAndRetriesMissingSegmentsOnce` 通过（系统段 nil、应用段展示、`isComplete == false` 驱动 `overview.storage.incomplete` 文案 `OverviewView.swift:220-224`）。
- AC-004 re_verified：同用例断言部分结果落盘（`saved.sums.system == nil`）、`testPartialHistoricalCacheRendersFirstThenCompleteScanOverwrites` 断言旧缓存先渲染后补全并覆盖；TTL/失效下的复用偏差见 f001。
- AC-005 re_verified（代码层）：`startEstimate` 创建非结构化 `Task`（`OverviewViewModel.swift:359-362`），不随视图 `.task` 取消；用例本身的取消模拟问题见 f005。
- AC-006 re_verified：`testCancelledScanDoesNotPersistAnything`、`testSystemSegmentIsUnavailableWhenAnyChildProbeFails` 独立重跑通过。
- AC-007 re_verified（代码审阅）：`AppDependencies.swift:699` 估算通道 `timeout: 600`；测试缺口见 f004。
- AC-008 re_verified：`testNoEyebrowCopyRemainsAnywhere` 通过；`rg` 全源码 eyebrow 仅剩测试断言与文档，catalog 11 个 eyebrow 键全删，9 个页面头全部经 `MolePageHead` 新签名渲染。
- AC-009 trust_prior：真实渲染需 GUI/demo 截图，工作区无截图产物，依赖实施侧截图对照；源码断言 `testOverviewCardsShareOneFixedHeight` 通过（4 处共用 264pt 常量）。

coverage = 8 / 9

reviewed_scope: dc071cc16a8594d1

verdict: FAIL

## Round 2 (2026-10-17T13:47:00+08:00)

审查范围：`git -C '/Users/karson/kar/code/zmole_t040' diff c4a338897084ae66378113b0e88061f9c4f3e397` 当前工作区全量（volatile 全测独立重跑：`xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 277 tests / 0 failures / TEST SUCCEEDED，2026-10-17T13:45:53+08:00；OverviewCacheTests 18/0、PageHeadAdoptionTests 6/0）。

### 前轮 finding 复核

- **t040_gen_f001（important）：修不彻底，blocker 仍在。** 失效信号分支已真修：`OverviewViewModel.swift:361` 现为 `fillMissingOnly = !estimateInvalidated && !isCacheStale && sums?.isComplete == false`，写失效时忽略 partial 全量重探；`testInvalidationRescansResolvedSegmentsInsteadOfOnlyFilling`（`tests/unit/OverviewCacheTests.swift:464`）断言 /Applications 被重探，独立重跑通过。但 TTL/时间戳分支原样存在：
    - fill-only 扫描（存在复用段）完成后仍 `storageCache?.save(merged, capturedAt: now())` 并刷新内存 `cacheEntry`（`OverviewViewModel.swift:430-436`），被复用的已解析段拿到新的 capturedAt；
    - `isCacheStale` 只看这条被刷新过的内存条目（`:388-391`），而 `estimateNeedsRefresh` 对不完整 sums 恒为 true（`:349`），因此每次概览出现都会触发一次 fill-only 扫描并在完成后续命 capturedAt；只要用户在 6h 窗口内打开概览（或重启应用，落盘时间戳同样已续命），条目永不超过 TTL；
    - 补扫任务同样硬编码 `fillMissingOnly: true`（`:465`）。
    - 可复现失败场景：`/Users`（p013 原场景）或 `/System` 子项持久失败 → applications/system/developer 持续复用旧值，每次访问 capturedAt 续命；缺失段最终恢复后 merged 变完整但仍含超龄分段且 capturedAt=now，再冻结一个 TTL 周期。写失效信号对复用段已不再出现，此分支只剩 TTL 唯一兜底，而兜底被绕过。违反 `docs/specs/overview.md:13-14`「写入失效信号与缓存过期触发全量重算」。
    - 最小修复方向：fill-only 扫描完成且存在复用段时不刷新 `capturedAt`（沿用旧条目时间戳，或仅当本次无任何复用段才 `save`）；若确认「部分估算下复用段不参与 TTL」为有意语义，须改写 spec/blueprint 表述并补断言该语义的测试（代码内无此决策记录）。
- **t040_gen_f002（minor）：已消除。** `OverviewView.swift:45-59` 现为 `primeEstimate` → `startEstimate` → `await refreshHistory()`，扫描不再排在 history 之后；`onChange(of: usedBytes)` 走 `usedBytesDidChange` 只重派生「其他」。`testEstimateRunsWithoutUsedBytesAndOtherSegmentArrivesLater`（`OverviewCacheTests.swift:341`）独立重跑通过。
- **t040_gen_f003（minor）：已消除。** (a) 补扫唤醒先 `guard self.sums?.isComplete == false`（`:464`），完成态不会退化为全量探测；(b) `incompleteRetryScheduled` 在唤醒时先清（`:461`）再运行，运行中的扫描完成时会按 `:441-443` 检查 `!incompleteRetryScheduled` 重排——R 与 B 的两种交错（R 唤醒时 B 在跑 / B 完成时 R 已清标志）都在代码审阅下收敛到「有补扫或 B 自行重排」。`testIncompleteScanRendersPersistsAndRetriesMissingSegmentsOnce`（`:148`）断言恰好 1 次补扫且 `/Applications` 不复探。
- **t040_gen_f004（minor）：已消除。** `testEstimateLaneTimeoutIsTenMinutes`（`OverviewCacheTests.swift:517`）对 `AppDependencies.swift:699` 估算通道做 `timeout: 600` 源码断言；独立重跑通过。
- **t040_gen_f005（minor）：已消除。** `testEstimateTaskIsNotTiedToTheStartingCaller`（`:375`）在 gate 暂停（caller 仍挂起）期间 `caller.cancel()` 再断言扫描完成，取消确实落在扫描中；`waitUntilPaused` 超时改为 `XCTFail`（`:562-568`）。用例现在能区分「随启动者取消」的实现。
- 撤回：无。

### 本轮新发现

#### t040_gen_f006 - 写失效信号在扫描进行中被静默丢弃，后续无补偿全量重扫

- 严重度：minor
- 锚点：`docs/specs/overview.md:13`「写入失效信号…触发全量重算」；行为缺陷：写操作完成时若估算扫描在飞，失效的全量重算被推迟到下一次触发。
- 位置：`src/zmole/Features/Overview/OverviewViewModel.swift:360`（`guard !isEstimating` 直接丢弃）、`:438-443`（扫描期间失效只保留标志、不链式重扫）、`:454-465`（补扫硬编码 fill-only，不消费失效）；`src/zmole/Features/Overview/OverviewView.swift:56-59`。
- 问题：可复现——用户在清理页发起操作后立即返回概览；估算扫描正在跑（如 `/Users` 分钟级探测）；操作完成触发 `invalidatePreviews` → `onChange` 的 `startEstimate` 因 `isEstimating` 被丢弃；在飞扫描完成时 `invalidationCount != invalidationsAtStart` 仅保留 `estimateInvalidated = true`（`:438-440`），不安排后续扫描；若该次为不完整扫描，补扫也只探测缺失段。用户停留在概览期间界面持续展示写操作前的分段值，直到下一次触发（离开再进入、或新失效）。该缺口在 diff_anchor 版本已存在（前轮未报），非本轮修复引入，但由新触发器接线触及。
- 建议：`runEstimate` 成功路径末尾若 `estimateInvalidated` 仍为 true（失效在扫描期间发生且未清除），追加启动一次全量 `startEstimate`；或让补扫任务在 `estimateInvalidated` 时改走全量。

### 结论（Round 2）

- 前轮 finding 复核：f002–f005 已消除；f001 修不彻底（失效分支已修，TTL/capturedAt 续命分支仍在），仍属未解决 important。
- 本轮新发现：1 条（minor，f006）。
- 未进表的提示：AC-009 仍无截图产物（trust_prior 同前）；264pt 卡高在 incomplete 态约 284pt 内容的贴边风险与第 1 轮相同，未达裁切/遮挡判定；`docs/design/*.html` 参考 demo 的 `.eyebrow` 属物料非界面文案，同前。
- 总体判断：契约主体与 4/5 条前轮 finding 已落实（277 例全绿复验），但 f001 的 TTL 兜底被「部分扫描刷新 capturedAt」绕过，已解析段可无限期超过 6h TTL 仍以权威值展示/落盘，属未解决 important，本轮 FAIL。
- 系统性 follow-up：无（f001 残余与 f006 建议本 task 内修复）。

#### AC 复验方式（Round 2）

- AC-001 re_verified：独立重跑 `testEstimateRunsWithoutUsedBytesAndOtherSegmentArrivesLater`；`OverviewView.swift:45-52` 不再等待 status 采样与 history。
- AC-002 re_verified：同用例断言 usedBytes 迟到后 `otherBytes == 500 - (40+25+30+60)` 且扫描次数不增。
- AC-003 re_verified：独立重跑 `testIncompleteScanRendersPersistsAndRetriesMissingSegmentsOnce`（系统段 nil、应用段展示、isComplete 驱动「估算不完整」文案）。
- AC-004 re_verified：同用例断言部分结果落盘（`saved.sums.system == nil`）；`testPartialHistoricalCacheRendersFirstThenCompleteScanOverwrites` 断言先渲染缓存再补全覆盖。
- AC-005 re_verified：`testEstimateTaskIsNotTiedToTheStartingCaller`（caller 挂起期间取消，扫描完成）+ `startEstimate` 非结构化 Task（`OverviewViewModel.swift:362-365`）。
- AC-006 re_verified：独立重跑 `testCancelledScanDoesNotPersistAnything`、`testSystemSegmentIsUnavailableWhenAnyChildProbeFails`。
- AC-007 re_verified：独立重跑 `testEstimateLaneTimeoutIsTenMinutes` + 代码审阅 `AppDependencies.swift:699`。
- AC-008 re_verified：独立重跑 `testNoEyebrowCopyRemainsAnywhere`（catalog 11 个 eyebrow 键全删、UtilityUI/OverviewView 源码无 eyebrow、9 个页面头新签名）。
- AC-009 trust_prior：真实渲染需 GUI/demo 截图，工作区仍无截图产物；依赖实施侧截图对照（源码断言 `testOverviewCardsShareOneFixedHeight` 通过，4 处共用 264pt）。

coverage = 8 / 9

reviewed_scope: 8a5c86c7b37ffec5

verdict: FAIL

## Round 3 (2026-10-17T13:56:00+08:00)

审查范围：`git -C '/Users/karson/kar/code/zmole_t040' diff c4a338897084ae66378113b0e88061f9c4f3e397` 当前工作区全量。第 2 轮报告后仅 `src/zmole/Features/Overview/OverviewViewModel.swift`（mtime 13:49:48）与 `tests/unit/OverviewCacheTests.swift`（13:50:37）被改动，其余 25 个交付文件与第 2 轮一致（mtime ≤13:40，逐文件核对）。独立重跑：`OverviewCacheTests` 20 tests / 0 failures（13:53:54）、全量 279 tests / 0 failures / TEST SUCCEEDED（13:54 结束）。工作区无 reviewer 不可见的未跟踪交付文件（仅本报告为流程文件）。

### 前轮 finding 复核

- **t040_gen_f001（important）：已消除。** 三个漏洞点逐一以当前 diff 核实：
    - `OverviewViewModel.swift:361`：`fillMissingOnly = !estimateInvalidated && !isCacheStale && sums?.isComplete == false`，缓存过期或写失效一律全量；
    - `:428-429`：`allowFill = fillMissingOnly && !estimateInvalidated`；扫描期间落下的失效标记会把已排定的补扫升级为全量探测（覆盖第 2 轮指出的 `:471` 硬编码 fill-only 路径）；
    - `:436-442`：`capturedAt = partial == nil ? now() : (cacheEntry?.capturedAt ?? now())`，`partial` 非空当且仅当存在复用段，此时落盘与内存 `cacheEntry` 均沿用旧时间戳；`:388-391` 的 `isCacheStale`、`:344-352` 的 `estimateNeedsRefresh` 因此基于未续命的时间戳判定。
    - 全路径复核：唯一 `save` 点在 `:437`；`partial == nil` 与「四路径全量重探」等价（`fillMissingOnly=false` 或 `sums.isComplete` 时 partial 恒为 nil），不存在第二条时间戳续命路径；fill-only 完成态（复用段 + 新补齐段）保持旧 capturedAt，陈旧复用段无法再无限期绕过 6h TTL。第 2 轮的可复现失败场景（每次概览出现 fill-only 续命 → 条目永不过 TTL）链路已断。
    - 新测试 `testFillOnlyScanDoesNotRefreshTheCacheTimestamp`（`OverviewCacheTests.swift:535`）独立重跑通过：T+5h 的 fill-only 扫描补全后 `saved.capturedAt` 仍为原 capture（`:556-559`），`clock.advance(TTL+60)` 后 `estimateNeedsRefresh == true`（`:563-564`）。`testInvalidationRescansResolvedSegmentsInsteadOfOnlyFilling`（`:467`）仍通过。`testPartialHistoricalCacheRendersFirstThenCompleteScanOverwrites` 的 capturedAt 断言改为 `== oldCapture`（`:261-264`）：断言严格度未降，且正是 f001 建议的语义（「保存/重试时不为复用段刷新 capturedAt」），非「把预期改成实现输出」的弱化。
- **t040_gen_f006（minor）：修不彻底（完成态分支仍存在）。** 补扫升级已落实且可判别：`testInvalidationDuringScanEscalatesFollowUpToFullRescan`（`:567`）断言首次 fill-only（1 次探测，缺升级实现则为 2 次）后升级补扫探测全部四段（共 5 次），独立重跑通过。但 f006 的完成态分支未覆盖：在飞扫描期间收到失效、且该扫描以完整 merged 结束（四段全部解析）时，`:447` 的补扫条件 `!merged.isComplete` 为假，不安排任何补偿；`estimateInvalidated` 保持 true（`:444-446`）而界面无任何标记，用户停留概览期间继续看到可能早于写入的分段值；该次 merged 还以 `capturedAt = now()`（partial==nil）落盘（`:436-437`），下次启动在 TTL 内会当作新鲜缓存直接渲染而不重扫。附带效应：标志保持 true 期间再次收到失效时 `Published` 值不变，`OverviewView.swift:56-59` 的 `onChange` 不再触发，页面内只能靠离开再进入（`.task` → `startEstimate`，此时 `estimateNeedsRefresh` 为 true 会全量重扫）自愈。触发窗口窄（用户须在写操作完成瞬间正处于概览且扫描在飞）、离开页面即恢复，维持 minor（与第 2 轮一致）。建议：`runEstimate` 成功路径在 `invalidationCount != invalidationsAtStart` 且未安排补扫时追加一次全量 `startEstimate`，或对失效与扫描重叠的写入把 capturedAt 保守取旧值。
- **t040_gen_f002（minor）：未回退。** `OverviewView.swift:45-52` 仍为 `primeEstimate` → `startEstimate` → `await refreshHistory()`。
- **t040_gen_f003（minor）：未回退。** `OverviewViewModel.swift:460-473` 保留唤醒置 `incompleteRetryScheduled = false`、`guard sums?.isComplete == false`，`:447` 保留 `!incompleteRetryScheduled` 重排；`testIncompleteScanRendersPersistsAndRetriesMissingSegmentsOnce`（`:148`）独立重跑通过。
- **t040_gen_f004（minor）：未回退。** `testEstimateLaneTimeoutIsTenMinutes`（`:520`）通过；`AppDependencies.swift:699` 仍为 `timeout: 600`。
- **t040_gen_f005（minor）：未回退。** `testEstimateTaskIsNotTiedToTheStartingCaller`（`:378`）、`ScanGate.waitUntilPaused` 的 `XCTFail`（`:651-657`）通过。
- 撤回：无。

### 本轮新发现

0 条。七个视角对第 3 轮 delta（`allowFill`、capturedAt 条件、两个新测试）逐项过检：安全（无外部输入/secret/日志变更）、正确性（上述路径推演 + 20/279 全绿）、契约（`startEstimate`/`runEstimate`/`loadSums(filling:)` 签名未变）、性能（升级补扫仅在失效标记下触发，符合「失效全量」契约）、架构（无新耦合）、健壮性（无新增吞错）、测试（两个新用例均可判别旧实现；未发现恒真/弱化断言）。

### 结论（Round 3）

- 前轮 finding 复核：f001 已消除（TTL/capturedAt 续命链路闭合）；f002–f005 未回退；f006 修不彻底（完成态分支无补偿），维持 minor。
- 本轮新发现：0 条。
- 未进表的提示：AC-009 仍无截图产物（trust_prior，同前两轮）；`OverviewView.swift` 264pt 卡高在 incomplete 态的贴边风险同前，未达裁切/遮挡判定；`docs/design/*.html` 参考 demo 的 `.eyebrow` 属物料非界面文案；本轮改动面仅 2 文件，无范围外观察。
- 总体判断：第 2 轮唯一 blocker（f001）的 TTL 兜底已被真实闭合（fill-only 不再刷新 capturedAt、失效/过期一律全量、补扫可升级），f002–f005 未回退，全量 279 例独立复跑全绿；f006 残余完成态分支为窄窗口 minor，非阻断。
- 系统性 follow-up：无（f006 残余建议本 task 内一并修复，或在 task.md 处置表明确遗留并给理由）。

#### AC 复验方式（Round 3）

- AC-001 re_verified：独立重跑 `testEstimateRunsWithoutUsedBytesAndOtherSegmentArrivesLater`；`OverviewView.swift:45-52` 顺序不变。
- AC-002 re_verified：同用例断言 usedBytes 迟到后 `otherBytes == 500 - (40+25+30+60)` 且扫描次数不增。
- AC-003 re_verified：独立重跑 `testIncompleteScanRendersPersistsAndRetriesMissingSegmentsOnce`（系统段 nil、应用段展示、`isComplete` 驱动「估算不完整」文案 `OverviewView.swift:219-223`）。
- AC-004 re_verified：同用例断言部分结果落盘；本轮重点复验 `testFillOnlyScanDoesNotRefreshTheCacheTimestamp`（缓存时间戳不再被 fill-only 续命、TTL 后可再触发全量）与 `testPartialHistoricalCacheRendersFirstThenCompleteScanOverwrites`。
- AC-005 re_verified：`testEstimateTaskIsNotTiedToTheStartingCaller`（caller 挂起期间取消，扫描照常完成）+ `startEstimate` 非结构化 Task（`OverviewViewModel.swift:362-365`）。
- AC-006 re_verified：独立重跑 `testCancelledScanDoesNotPersistAnything`、`testSystemSegmentIsUnavailableWhenAnyChildProbeFails`。
- AC-007 re_verified：独立重跑 `testEstimateLaneTimeoutIsTenMinutes` + 代码审阅 `AppDependencies.swift:699`。
- AC-008 re_verified：全量重跑含 `testNoEyebrowCopyRemainsAnywhere` 通过（本轮未触及该路径）。
- AC-009 trust_prior：真实渲染需 GUI/demo 截图，工作区仍无截图产物；依赖实施侧截图对照（源码断言 `testOverviewCardsShareOneFixedHeight` 全量重跑通过）。

coverage = 8 / 9

reviewed_scope: e82a4d342c2f2bba

verdict: PASS
