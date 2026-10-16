# Code review — t025 命令并发通道按类型区分

- reviewer: code
- review_level: full
- diff_anchor: `156c58d3f779f9e3562e1f727c0fe1e7c9d50127`
- target: `git -C zmole_t025 diff 156c58d3f779f9e3562e1f727c0fe1e7c9d50127`
- head: `156c58d3f779f9e3562e1f727c0fe1e7c9d50127`（工作区未提交）

## 变更概览

- 新增 `src/zmole/App/MoleCommandLanes.swift`：9 条一次性通道（analyze/history/uninstall/installer/statusCommand/cleanCommand/optimize/purge/estimate）+ status 流、clean 流；`.demo`、`.unavailable`、`makeCommandBridges`。
- `AppDependencies`：每个一次性消费者改为拿独立 `MoleBridge`，暴露 `lanes`；新增 `estimate` 通道（p007）。
- `UnavailableMoleProcess/Streaming` 由 `private` 改 `internal`，供 `.unavailable()` 复用。
- 新增 `tests/unit/CommandConcurrencyTests.swift`（5 用例）。
- `Zmole.xcodeproj/project.pbxproj` 登记两个新文件；`docs/blueprint/architecture.md` 更新通道模型。

## 门禁复核（本地实跑）

- `xcodebuild test -scheme Zmole -destination 'platform=macOS'` → **183 passed, 0 failures**（含新增 5 例）。
- `pytest .repo_template/tests -q -m contract` → **147 passed, 367 deselected**。
- `bash tests/integration/clean_trash_test.sh` → all cases passed。
- `bash tests/integration/installer_interface_test.sh` → all cases passed。

## AC 覆盖

- **AC-001 PASS**：五个必测只读命令映射到互不相同的桥（`analyze=bridges[0]`、`history=bridges[1]`、`uninstall=bridges[2]`、`installer=bridges[3]`、`statusCommand=bridges[4]`），桥实例互不复用 → 一个只读命令挂起不阻塞另一个。`testIndependentBridgesDoNotShareBusy` 以 `/bin/sleep` 阻塞一条桥，断言另一条 `isBusy == false` 且能跑通 `exitCode 0`。
- **AC-002 PASS**：`status --watch` 走 `statusStream`（独立 `streamBridge`），只读 `status --json` 走 `statusCommand`，`testActiveStreamDoesNotBlockAnotherLane` 覆盖流挂起期间另一桥可运行。
- **AC-003 PASS**：写入命令改用各自独立桥（clean/uninstall/optimize/purge/installer），互斥只由 `OperationCoordinator` 租约承担。逐一核对：`MaintenanceViewModel`（optimize/purge）`acquire`→`run`→`release`；`CleanViewModel`、`UninstallViewModel`、`InstallersViewModel.confirmRemoval` 均在 spawn 前 `acquire`、结束 `release`/`defer release`，lease 覆盖整个 await 窗口。whitelist/purgePaths 写入不 spawn mole 亦持租约。故不会同时 spawn 两个写入。
- **AC-004 PASS**：各页 in-flight 守卫（`session.isBusy`/`isListing`/`isRemoving`/`canConfirm`）未改动，语义保持；`testCleanDuplicateExecutionCreatesOneProcess` 仍覆盖“同页重复提交只飞一个”。

## Findings

### t025_code_f001

- severity: low
- file: `src/zmole/Features/Overview/OverviewView.swift:24-27`、`src/zmole/Features/Overview/StorageEstimate.swift:76-77`
- 问题：两处注释以“一次性命令共用同一条命令桥（单 in-flight process）”解释为何 estimate/四段目录探测必须串行。本 task 已给 estimate 分配独立通道（`AppDependencies.swift:428-432`），该理由已失效，注释与实现不符。
- 证据：`OverviewView` 注释“One-shot commands share the command bridge, so the estimate is loaded only after history finishes”；`StorageEstimate` 注释“The command bridge allows one in-flight process, so the four directory probes run sequentially instead of concurrently”。
- 影响：仅文档/可读性。串行行为本 task 有意保留（spec 非范围：不改行为），无需改逻辑。
- 建议：更新注释，说明串行是保留的既有行为（避免并发分析放大资源占用），而非通道限制。

### t025_code_f002

- severity: low
- file: `src/zmole/App/AppDependencies.swift:418-422, 433-436`
- 问题：`historyLoader`（基于 `historyBox`，即 `bridges[1]`）同时注入 `historyViewModel` 与 `overviewViewModel`。概览与 History 页共用同一条 `history` 通道，两处发起 `history --json` 时会互相 busy。这是 AC-001 语义下残留的只读-只读耦合。
- 证据：`:422 historyViewModel = HistoryViewModel(loader: historyLoader)`；`:435 historyLoader` 传入 `OverviewViewModel`。
- 影响：窄。两页不同时可见，且切页时 SwiftUI `.task` 取消会经 `withTaskCancellationHandler` 终止底层进程，实际并发窗口极小；`history --json` 亦为快命令。spec 只显式要求概览 *estimate* 独立通道（p007），现已满足。
- 建议：可接受现状；若追求“每消费者一通道”的一致性，为概览再分配一条 history 通道（第 10 条）或让概览复用 `history` 结果缓存。非阻塞。

### t025_code_f003

- severity: low
- file: `tests/unit/CommandConcurrencyTests.swift:6-11`
- 问题：测试只断言 `makeCommandBridges()` 产出 9 条互异桥，未断言 `AppDependencies` 把各消费者装配到 *不同* 通道。装配层如果错位复用同一桥（例如 analyze 与 history 指向 `bridges[0]`），现有测试不会失败，而 AC-001/AC-003 的实际失败点正是装配层。
- 证据：`testCommandBridgesAreDistinct` 仅覆盖桥本身；`AppDependencies.init` 的 `bridges[i]` 映射无测试。
- 影响：回归防护偏弱（假绿风险）。AC-003 的用例 `testWriteLeaseIsMutuallyExclusiveAcrossOperations` 只单测 `OperationCoordinator`（且是既有行为），未验证写入确实经租约、未 spawn。
- 建议：若 `AppDependencies` 可注入桥工厂，补一条装配级断言（各通道 identity 互异、estimate 独立于 analyze）；否则至少在 `MoleCommandLanes` 上补一条构造映射测试。

### t025_code_f004

- severity: low
- file: `tests/unit/CommandConcurrencyTests.swift:67-73`
- 问题：`waitUntilBusy` 超时后抛 `XCTSkip`。一旦桥因回归不再进入 busy，`testIndependentBridgesDoNotShareBusy` / `testActiveStreamDoesNotBlockAnotherLane` 会被标记 skipped 而非 failed，`isBusy` 断言被绕过。
- 影响：断言弱化，可能掩盖回归。
- 建议：超时抛 `XCTFail`（或返回布尔由调用方断言），使未达 busy 直接失败。

## 结论

实现方向正确、范围克制，符合 spec 契约：只读命令按消费者分通道并发、写入靠 `OperationCoordinator` 单一租约真串行、`status --watch` 与 clean dry-run 流各占独立桥、概览 estimate 拿到独立通道（p007）。demo/unavailable 回退路径行为与改动前一致（demo 单进程共享、cleanStream 均为 nil），无永久回归。四个 AC 均有可运行的自动覆盖，本地四类门禁全部通过。

遗留均为 low：两处注释因改动而过时、概览与 History 页共用 history 通道的窄耦合、装配层与 AC-003 端到端断言偏弱、`waitUntilBusy` 用 `XCTSkip` 弱化断言。均不阻塞合入，建议随手修 f001/f004。

verdict: PASS

## Round 2 (2026-10-16T21:50:22+08:00)

- diff 复核：`git -C zmole_t025 diff 156c58d3f779f9e3562e1f727c0fe1e7c9d50127`。生产文件（`MoleCommandLanes.swift` 79 行、`AppDependencies.swift` 76 行）与 round 1 逐行一致，仅测试文件扩写（74 → 154 行）。无生产逻辑变更，回归面局限于测试。
- 门禁实跑：`xcodebuild test` → **184 passed, 0 failures**；`pytest .repo_template/tests -q -m contract` → **147 passed, 367 deselected**。与声明一致。

### Dispositions

- t025_code_f003 — **FIXED**。新增 `testAppDependenciesWiresDistinctLanes`：直接构造生产 `AppDependencies()`，断言 9 条一次性通道 identity 互异，并断言概览 `estimate` 与磁盘页 `analyze` 不同桥。装配层错位复用现在会被捕获。另新增 `testTwoWriteViewModelsCannotRunConcurrently`：`OptimizeViewModel` 持租约阻塞期间 `PurgeViewModel` 并发提交被拒为 `operation.error.busy` 且 `isPreviewing == false`，把 AC-003 从“单测协调器”提升到“经真实 VM + 独立通道 + 共享协调器”的端到端断言。
- t025_code_f004 — **FIXED**。`waitUntilBusy` 超时改为 `XCTFail("bridge never became busy")`；AC-001/AC-002 用例在桥未进入 busy 时直接失败而非静默 skip。
- t025_code_f001 — **WON'T FIX（已接受）**。两处过时注释保留；纯可读性，不阻塞。
- t025_code_f002 — **WON'T FIX（已接受）**。概览与 History 页共用 `history` 通道为有意设计：两页不同时可见，切页经 `.task` 取消终止底层进程，实际并发窗口可忽略。

### t025_code_f005

- severity: low
- file: `tests/unit/CommandConcurrencyTests.swift:83-95`
- 问题：`testSameBridgeRejectsConcurrentRun` 注释标注为“AC-004: duplicate submission on one lane”，但该用例验证的是同一条 `MoleBridge` 的第二次 `run` 被拒为 busy，属通道级机制；AC-004 的“同一功能页一次请求未完成前不得重复提交”实际由页面 session 守卫（`testCleanDuplicateExecutionCreatesOneProcess`）覆盖。标签与断言对象不吻合，属注释失准，非逻辑缺陷。
- 建议：将注释改为通道级 busy 语义，或补一条页面级重复提交断言。非阻塞。

### 回归扫描

- `BlockingProcessSpy`（`:112-149`）为 actor，测试路径只走 `finish()`；`cancel()` 与 `finish()` 均无“是否已 resume”守卫，理论上双调用会崩溃，但当前未被触发，属测试夹具潜在脆弱点，不计为 finding。
- 未发现新的生产逻辑回归；四个 AC 覆盖较 round 1 增强（AC-001/002 桥级、AC-003 VM 端到端、AC-004 依赖既有 clean 页用例 + 桥级 busy）。

新增 finding：1（f005, low）。均不阻塞。

reviewed_scope: 6d211272f4bcb643

verdict: PASS
