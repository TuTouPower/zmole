# Task review t016（reviewer_focus: 通用）

- task：`t016_overview_status`
- spec：`docs/tasks/t016_overview_status/spec.md`
- diff_anchor：`43243a5d0d7b3bc9d8f832717358f7a792358de6`
- target：`git -C '/Users/karson/kar/code/zmole_t016' diff 43243a5d0d7b3bc9d8f832717358f7a792358de6`
- round：1
- reviewed_at：2026-10-16T17:57:26+08:00

## Findings

### t016_gen_f001 - 生产路径共享单个 MoleBridge，watch 与概览的 analyze/history 互斥，AC-003/AC-004 端到端失效

- 严重度：important
- 锚点：AC-003 / AC-004 + 失败场景：真机（捆绑 mole，非 demo）打开概览页，watch 常驻占用 bridge，五段估算与最近操作始终拿不到数据。
- 位置：`src/zmole/App/AppDependencies.swift:323`（`process = bridge; streaming = bridge`）、`src/zmole/App/AppDependencies.swift:357`（analyze/history loader 复用同一 `processBox.process`）、`src/zmole/MoleBridge/MoleBridge.swift:75` 与 `MoleBridge.swift:103`、`src/zmole/Features/Overview/OverviewViewModel.swift:89`
- 问题：
    - `AppDependencies` 里 `process` 与 `streaming` 是同一个 `MoleBridge` 实例；预览/状态/分析/历史的所有 loader 都走这个实例。
    - `MoleBridge.run` 与 `MoleBridge.stream` 都先 `guard activeRunner == nil else { throw/return .busy }`。概览页按 t016 的设计会让 `status --watch` 常驻（`AppShellView.updateStatusWatch` 对 `.overview` 调 `start()`），因此 `activeRunner` 被 watch 占住。
    - 概览的 `OverviewViewModel.refresh` 通过同一 bridge 发起 4 次 `analyze`（`StorageEstimateLoader.load` 的 `async let`）+ 1 次 `history`。这些调用会命中 `.busy`：analyze 被 `try?` 吞掉返回 nil → `StorageBreakdown` 全 nil → 环永远占位；history 抛错 → `recentOperations = []`，卡片显示“还没有操作记录”。
    - 反向也存在：若首个 analyze 先占用 bridge，watch 的 `stream` 立即以 `.busy` 结束，`StatusWatchService.streamEnded` 终止无人重试 → 概览一直“等待首个状态采样”。
    - 单测用注入 fake 绕开 `MoleBridge`，demo 用独立的 `DemoMoleProcess`/`DemoMoleStreaming`（无 busy 守卫），所以此冲突在测试与 demo 中都被掩盖。
- 建议：让概览的目录估算/历史不与该常驻 watch 争用同一 bridge（例如为一次性命令使用独立 `MoleBridge` 实例，或让 `MoleBridge` 对命令排队/区分 stream 通道），否则 AC-003/AC-004 在真机无法达成。需在真机路径（非 fake）补一条集成级验证。

### t016_gen_f002 - 估算刷新触发器绑在 `snapshot?.collectedAt`：demo 夹具无该字段永不重算，真机每 1s 重算

- 严重度：important
- 锚点：AC-003 + 失败场景：`--demo --demo-page overview` 首屏进入概览，五段环一直显示占位。
- 位置：`src/zmole/Features/Overview/OverviewView.swift:22`、`OverviewView.swift:232`、`OverviewView.swift:243`
- 问题：
    - `.onChange(of: statusViewModel.snapshot?.collectedAt)` 是唯一的“状态到达后重算估算”途径。首帧 `load()` 因 `snapshot == nil` 以 `usedBytes = nil` 调用刷新，`other` 段必为 nil。
    - `DemoMoleProcess`/`DemoMoleStreaming` 的 status 夹具不含 `collected_at`（`AppDependencies.swift:170`、`AppDependencies.swift:237`），`StatusSnapshot.collectedAt` 恒为 nil，`.onChange` 的值为 nil→nil 不触发 → 概览在 demo 首屏永不重算，环保持灰色占位、图例全 “—”。
    - 真机 mole 每帧带 `collected_at`，于是每 1 秒触发一次 `loadBreakdown()`，即每次重新 spawn 4 个 `analyze` + 1 个 `history`（目录全量扫描），与 f001 叠加后既失败又空转。
- 建议：不要用 `collectedAt` 变化驱动目录估算。目录体积变化慢，应在概览页出现时取一次已用空间并只加载一次（或在 `usedBytes` 首次可用时补算一次），而不是每个采样点重算。

### t016_gen_f003 - AC-006：网络缺失显示 “—”，未按 spec 显示“未知”

- 严重度：minor
- 锚点：AC-006（“对缺失的温度或网络显示未知”）
- 位置：`src/zmole/Features/Status/StatusView.swift:231`（`rate(_:)` 返回 "—"）、`StatusView.swift:161`（`networkPanel`）
- 问题：新增 `status.unknown`（“未知”）用于温度/僵尸进程（`StatusView.swift:183`、`StatusView.swift:188`），但网络上下行缺失仍走 `rate(nil) -> "—"`。语义上都是“无数据”，但与 AC-006 字面要求及同页温度处理不一致；且无测试覆盖。
- 建议：网络缺失统一改为 `status.unknown`，或与 spec 明确 “—” 即未知、二者取一。

### t016_gen_f004 - 可测性声明与实际覆盖不符：AC-006/AC-007 无自动断言，AC-002 断言偏弱

- 严重度：minor
- 锚点：spec「可测试性声明：AC-001–AC-007 自动断言」
- 位置：`tests/unit/OverviewTests.swift`（全文）
- 问题：新增测试只覆盖公式、Metrics、趋势阈值、quick action 目的地集合、ViewModel 加载与 `StatusSnapshot` 字段解码。AC-006（缺失字段 UI/进程行无结束动作）、AC-007（离页停止 watch、暂停隐藏圆点）无任何自动断言；AC-002 只断言目的地集合与不含 `.installers`，未证明点击不触发清理/优化执行。
- 建议：补 AC-006/AC-007 断言（可对 `StatusViewModel`+`StatusWatchProviding` 替身断言离页后 `stop` 被调用、暂停后 `isSampling == false`；对格式化后的展示串断言“未知”），并在 spec 或测试中说明 quick action 仅导航的验证方式。

### t016_gen_f005 - 概览与 AppShellView 双重 start 生命周期；stop 改为异步 Task 引入竞态

- 严重度：minor
- 锚点：AC-007 + 行为缺陷
- 位置：`src/zmole/Features/Overview/OverviewView.swift:232`（`load()` 内 `statusViewModel.start()`）、`src/zmole/App/AppShellView.swift:95`（`updateStatusWatch`）
- 问题：
    - `AppShellView` 已统一按目的地 start/stop，`OverviewView.load()` 仍自行 `start()`。虽然 `guard snapshot == nil, !isSampling` 大多能挡住，但 onAppear 与 `.task` 执行顺序不保证，可能在首帧对同一 watchTask 反复 `cancel()`+重订阅，产生短暂双订阅。
    - 离页走 `Task { await statusViewModel.stop() }`：`stop()` 先 `watchTask?.cancel()` 再 `await watchService.stop()`，而 service 的 `stop/pause` 有 `guard subscribers.count <= 1`。快速“离开→返回”时，排队中的 stop 可能取消刚建立的订阅；不过依赖 `removeSubscriber` 在订阅清空时兜底停止进程，实际泄漏风险低，主要是状态抖动。
- 建议：去掉 `OverviewView.load()` 中重复的 `start()`，把 watch 生命周期完全交给 `AppShellView`；离页 stop 直接同步调用并避免跨 tick 排队。

### t016_gen_f006 - `refresh` 无重入保护，多次并发会互相覆盖

- 严重度：minor
- 锚点：行为缺陷（资源/正确性）
- 位置：`src/zmole/Features/Overview/OverviewViewModel.swift:89`
- 问题：`refresh` 无 in-flight 判断；配合 f002 的每秒触发与慢速 `analyze`，会出现多个刷新并发，后到者用旧 `usedBytes` 覆盖 `breakdown`，`isLoading` 也被并发置位/复位。
- 建议：加 `isLoading` 短路或任务去重；估算与历史分离加载，避免互相覆盖。

## 结论

- 本轮新发现：6 条（important ×2，minor ×4）
- 未进表的提示：
    - `OverviewViewModel.errorMessage` 被赋值但概览未展示，history 失败时用户只看到“无记录”，掩盖了真实错误。
    - `StorageEstimateLoader` 对 analyze 返回空 `entries` 视为 0 而非缺失；只要命令成功但目录为空，会得到真实 0 段而非占位，边界语义可再确认。
    - `AppDestination`/`Localizable.xcstrings` 新增键齐全，`overview.title` 仍在；移除 `overview.placeholder` 引用后旧字符串残留，属无害冗余。
- 总体判断：功能骨架与公式、Metrics、趋势阈值、quick action 导航、`StatusSnapshot` 新字段解码实现清晰，单测有效覆盖可测部分。但生产路径存在共享 `MoleBridge` 互斥（f001）与估算刷新触发器缺陷（f002）两处 important 问题，使 AC-003/AC-004 在真机无法端到端达成，demo 又恰好掩盖之。需先修复后再验收。
- 系统性 follow-up：把“常驻 watch + 一次性命令共用单通道 bridge”的冲突作为架构级约束处理（`docs/blueprint/architecture.md` 的「进程生命周期」只描述了单页单进程，未覆盖同页 watch 与命令并存），否则后续任何“首页常驻采样 + 同页命令”的功能都会重现。

### AC 复验方式

- AC-001：`re_verified` — 代码 `OverviewMetrics`（`OverviewViewModel.swift:6`）映射快照，测试 `testOverviewMetricsMatchInjectedSnapshot` 断言健康分/CPU/可用磁盘。
- AC-002：`re_verified` — `OverviewQuickAction` 只存 `destination`，点击仅 `navigation.select`（`OverviewView.swift:186`）；测试断言目的地集合。执行侧未被断言。
- AC-003：`re_verified` — `StorageBreakdown.make` 公式 + `StorageEstimateLoader` 测试；但 UI 触发链存在 f001/f002，端到端未成立。
- AC-004：`re_verified` — `testOverviewViewModelLoadsBreakdownAndHistoryAndHandlesEmptyHistory` 覆盖有/无记录；但生产 busy 冲突（f001）使真机无记录可显。
- AC-005：`re_verified` — `OverviewTrend.minimumSamples = 3` + `testOverviewTrendNeedsMinimumSamples`，视图据此切“采样不足”。
- AC-006：`trust_prior` — 无测试；读码确认进程行为只读、温度缺失显示“未知”，但网络缺失显示“—”（f003）。
- AC-007：`trust_prior` — 无测试；读码确认 `AppShellView` 按目的地 start/stop、暂停时 `isSampling=false` 隐藏圆点，存在 f005 竞态。
- coverage = 5 / 7

verdict: FAIL

### Round 2 (2026-10-16T18:04:00+08:00)

复核方式：重跑 `git -C '/Users/karson/kar/code/zmole_t016' diff 43243a5d0d7b3bc9d8f832717358f7a792358de6`，读当前源；`xcodebuild test -scheme Zmole -destination 'platform=macOS' -only-testing:ZmoleTests/OverviewTests` → 12/12 通过（全量 121 通过为具报）。

#### 上轮 finding 处置

- f001（共享 MoleBridge busy 冲突）：**partially fixed**。`AppDependencies.swift:320` 起改为 `commandBridge`/`streamBridge` 两条独立 `MoleBridge`，watch 占流式桥、一次性命令占命令桥，watch↔命令冲突消除。但同属该类的“命令↔命令”冲突未处理：`StorageEstimateLoader.load`（`StorageEstimate.swift:76`）用 `async let` 并发发起 4 次 `analyze`，全部走同一条命令桥，`MoleBridge.run` 的 `guard activeRunner == nil` 会让其中 3 次立即抛 `.busy`，被 `try?` 吞成 nil。见新 finding f007。
- f002（估算刷新绑 `collectedAt`，逐 tick 重扫，demo 永不重算）：**resolved**。改为 `.task` 拉一次 history + `didLoadEstimate` 守卫的一次性估算（`OverviewView.swift:22`、`:232`），由 `usedBytes` 由 nil 变可用触发。demo 夹具无 `collected_at` 也能补算。
- f003（网络缺失显示 “—”）：**resolved**。新增 `StatusReadout`（`StatusReadout.swift`），temperature/rate/count 统一缺失→本地化“未知”；网络、磁盘 I/O、温度、僵尸进程均改走它。
- f004（AC-006/007 无断言）：**resolved**。补 `testStatusReadoutShowsUnknownForMissingValues`（AC-006）与 `testStatusViewModelStopEndsSamplingAndStopsTheSharedService`（AC-007，spy 断言 stop 被调用且 `isSampling` 归 false）。AC-002 仍仅断言目的地集合，未证明点击不触发执行（保留提示）。
- f005（OverviewView 重复 start）：**resolved**。`OverviewView` 已无 `statusViewModel.start()`，watch 生命周期仅由 `AppShellView.updateStatusWatch` 掌控。
- f006（refresh 无重入保护）：**resolved**。`OverviewViewModel.loadEstimate` 用 `isEstimating` 守门（`OverviewViewModel.swift:89`）。

#### 本轮新发现

### t016_gen_f007 - 五段估算的 4 次 analyze 并发打单条命令桥，3 次被判 busy

- 严重度：important
- 锚点：AC-003 + 失败场景：真机（捆绑 mole）打开概览，五段环因缺 3 段永远占位。
- 位置：`src/zmole/Features/Overview/StorageEstimate.swift:75`、`src/zmole/App/AppDependencies.swift:357`（单条 `commandBridge`）、`src/zmole/MoleBridge/MoleBridge.swift:75`
- 问题：`load` 用 `async let` 并发跑 `/Applications`、`/System`、`~/Library/Developer`、`/Users` 四次 `analyze`，全部复用同一条命令桥。`MoleBridge` 只允许一个 active runner，actor 在首个 `run` 的 `await` 处可重入，后到 3 次立即 `throw .busy`，被 `try?` 记为 nil；`isComplete` 恒 false → 环占位、图例全 “—”。单测 `testStorageEstimateLoaderSumsAnalyzeEntriesPerSegment` 注入自定义 `directorySize` 闭包，绕开桥，无法暴露；demo 用无 busy 守卫的 `DemoMoleProcess`，再次掩盖。
- 建议：将 4 次 analyze 串行化（逐个 `await`，一次只占一条命令桥），或为每次 analyze 使用独立桥/允许桥排队。修后需在真机路径（非注入闭包）补集成验证，确认 4 段都能拿到。

### t016_gen_f008 - architecture.md 项目符号被并到上一行（文档格式回归）

- 严重度：minor
- 锚点：文档一致性
- 位置：`docs/blueprint/architecture.md:33`
- 问题：`- 破坏性命令：…（预览 spawn 允许）。- \`clean --dry-run\` 的 …\` 两条项目符号被并成一行，丢失换行；非本任务语义改动，疑为编辑事故。
- 建议：恢复为两条独立 bullet。

### t016_gen_f009 - 双桥初始化失败的 fallback 仍会退化为单桥，重新引入冲突

- 严重度：minor
- 锚点：行为缺陷（边界）
- 位置：`src/zmole/App/AppDependencies.swift:320`–`:332`
- 问题：`else if let commandBridge = try? MoleBridge(), let streamBridge = try? MoleBridge()` 两条都成功才用双桥；任一失败则落入 `else if let bridge = try? MoleBridge()`，把 `process` 与 `streaming` 同设一条桥，回到 f001 冲突。实际两桥同源，通常同成同败，风险低。
- 建议：去掉会退化单桥的 fallback，或显式记录/Warn 退化路径。

#### AC 复验方式（Round 2）

- AC-001：`re_verified` — `OverviewMetrics` 映射 + `testOverviewMetricsMatchInjectedSnapshot`。
- AC-002：`re_verified` — 类型上 quick action 仅存 `destination`、点击仅 `navigation.select`；测试仍只断言目的地（执行未断言，提示保留）。
- AC-003：`re_verified`（单元）— `make` 公式 + loader 测试；但 f007 使真机五段无法齐备，端到端未成立。
- AC-004：`re_verified` — `refreshHistory` + `testOverviewViewModelLoadsBreakdownAndHistoryAndHandlesEmptyHistory`；命令桥与流式桥分离后 history 不再 busy。
- AC-005：`re_verified` — `OverviewTrend.minimumSamples` + 测试。
- AC-006：`re_verified` — `testStatusReadoutShowsUnknownForMissingValues` + `StatusReadout` 统一缺失→未知。
- AC-007：`re_verified` — `testStatusViewModelStopEndsSamplingAndStopsTheSharedService`（spy）+ `AppShellView` 单一生命周期。
- coverage = 7 / 7（单元层面；AC-003 端到端受 f007 阻断）

#### 结论（Round 2）

- 本轮新发现：3 条（important ×1 = f007；minor ×2 = f008、f009）
- 上轮 f002–f006 全部 resolved，f001 partially fixed。
- 总体判断：本轮修复方向正确，估算触发与缺失值显示均已达标；但 f001 只解决了 watch↔命令，遗留“命令↔命令”并发冲突（f007），使 AC-003 在真机仍无法端到端达成，demo/注入闭包继续掩盖。需修复后再验收。
- 系统性 follow-up：`StorageEstimateLoader` 的 4 路并发与 `MoleBridge` 单 runner 语义不匹配，应作为装配层约束统一处理（串行或每路独立桥），并补一条不依赖注入闭包的生产路径验证，避免同类“桥独占”问题再被 fake/demo 掩盖。

verdict: FAIL

### Round 3 (2026-10-16T18:07:03+08:00)

复核方式：重跑 `git -C '/Users/karson/kar/code/zmole_t016' diff 43243a5d0d7b3bc9d8f832717358f7a792358de6`，读当前源；`xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 121 passed / 0 failed（本机实测）。

#### 上轮 finding 处置

- f007（4 路 analyze 并发打单条命令桥）：**resolved**。`StorageEstimateLoader.load`（`StorageEstimate.swift:75`）改为顺序 `await` 四次目录探测，注释说明命令桥只允许一个 in-flight；4 次 analyze 不再互相 busy。
- f008（architecture.md 项目符号并行）：**resolved**。`docs/blueprint/architecture.md:33`–`:34` 已恢复为两条独立 bullet。
- f009（双桥初始化失败的 fallback 退化为单桥）：**resolved**。`AppDependencies.swift:320` 起双桥失败时直接落到 `UnavailableMoleProcess`/`UnavailableMoleStreaming`，不再共用一条桥。

#### 回归扫描（估算流与命令桥 / 状态 watch 的碰撞）

- 估算内部：4 次 analyze 顺序执行，互不 busy（已核对 `StorageEstimate.swift:75`）。
- 估算 vs history：`OverviewView.task`（`OverviewView.swift:21`）先 `await refreshHistory()`，history 完成后才进入等待/估算；同一命令桥上 history 与 analyze 不重叠。
- 估算 vs 状态 watch：watch 走独立 `streamBridge`（`AppDependencies.swift:323` 起），命令走 `commandBridge`，两条 `MoleBridge` 无共享 `activeRunner`，不互斥。
- watch 生命周期：`AppShellView` 仍为唯一 owner，`OverviewView`/`StatusView` 均不自起 watch；无回归。
- 结论：本轮估算路径在概览页内不再有桥独占冲突，f001/f007 类问题清除。

#### 本轮新发现

### t016_gen_f010 - 估算等待首帧 used-space 用固定 12s 轮询，超时后本次会话静默不加载

- 严重度：minor
- 锚点：AC-003 + 失败场景：慢机首帧 `status` 超过 12s，概览本次进入仍显示占位环。
- 位置：`src/zmole/Features/Overview/OverviewView.swift:21`–`:30`
- 问题：`.task` 里 `for _ in 0..<120 where usedBytes == nil { try? await Task.sleep(100ms) }` 是固定上限 12s 的轮询；若首个含 `disks.used/total` 的采样在窗口内未到，`loadEstimateIfNeeded()` 因 `usedBytes == nil` 直接返回，且无其他触发点（R2 的 `onChange` 已移除），本次停留概览不会再重试，须离开再返回。真机首帧通常远快于 12s，风险低。
- 建议：用 `onChange(of: usedBytes)` 或对状态快照的订阅替代固定轮询；或轮询超时后在快照到达时补一次触发。注：`for ... where` 在条件转真后仍空转剩余迭代（无 sleep），仅属实现观感，无功能影响。

### t016_gen_f011 - 依赖命令桥的跨页命令与估算仍可能瞬时 busy

- 严重度：minor
- 锚点：行为缺陷（边界）
- 位置：`src/zmole/App/AppDependencies.swift:357`（analyze/history loader 共用 `commandBridge`）
- 问题：`commandBridge` 被全 App 的一次性命令共享。若概览的四段估算仍在跑（可能数秒），用户切到 disk/history 页并触发命令，会命中 `busy`。属跨页瞬态，非本次新增（桥独占语义固有），但估算耗时较长会放大窗口。
- 建议：如需彻底消除，可让估算也使用独立桥或桥内排队；当前失败可重试，风险可接受。

#### AC 复验方式（Round 3）

- AC-001：`re_verified` — `OverviewMetrics` + `testOverviewMetricsMatchInjectedSnapshot`。
- AC-002：`re_verified` — 类型仅存目的地、点击仅 `navigation.select`；测试断言目的地（执行未断言，R1 提示保留）。
- AC-003：`re_verified` — `make` 公式 + loader 测试；f007 修复后 4 段共用同一命令桥顺序执行，真机可齐备；`usedBytes` 由首帧快照提供。剩余风险仅 f010 的超时边界。
- AC-004：`re_verified` — `refreshHistory` + `testOverviewViewModelLoadsBreakdownAndHistoryAndHandlesEmptyHistory`。
- AC-005：`re_verified` — `OverviewTrend.minimumSamples` + 测试。
- AC-006：`re_verified` — `testStatusReadoutShowsUnknownForMissingValues`。
- AC-007：`re_verified` — `testStatusViewModelStopEndsSamplingAndStopsTheSharedService` + `AppShellView` 单一生命周期。
- coverage = 7 / 7

#### 结论（Round 3）

- 本轮新发现：2 条（均 minor：f010、f011）
- 上轮 f007/f008/f009 全部 resolved；f001 的 watch↔命令与命令↔命令两处独占冲突均已消除。
- 总体判断：估算流已串行化并与 history、watch 分桥，AC-003 端到端障碍清除；余下为固定 12s 轮询与跨页瞬态 busy 两处 minor，不阻断验收。
- 系统性 follow-up：建议后续把“一次性命令桥”的独占语义在装配层统一成排队或每消费者独立桥，并在非注入路径补一条集成验证，避免同类问题再被 fake/demo 掩盖。

reviewed_scope: 234c474bffa6e051

verdict: PASS
