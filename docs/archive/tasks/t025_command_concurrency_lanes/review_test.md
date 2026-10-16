# Task review t025（reviewer_focus: test）

- task: t025_command_concurrency_lanes（命令并发通道按类型区分）
- spec: `docs/tasks/t025_command_concurrency_lanes/spec.md`
- review_level: full
- diff_anchor: `156c58d3f779f9e3562e1f727c0fe1e7c9d50127`
- target: `git -C '/Users/karson/kar/code/zmole_t025' diff 156c58d3f779f9e3562e1f727c0fe1e7c9d50127`（new files intent-to-add，非 `...HEAD`）
- round: 1
- reviewed_at: 2026-10-16T21:50:00+08:00

## 验证记录

- `xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 183 passed，0 failures。
- `xcodebuild test ... -only-testing:ZmoleTests/CommandConcurrencyTests` → 5 passed（`testCommandBridgesAreDistinct` / `testIndependentBridgesDoNotShareBusy` / `testSameBridgeRejectsConcurrentRun` / `testActiveStreamDoesNotBlockAnotherLane` / `testWriteLeaseIsMutuallyExclusiveAcrossOperations`）。
- `pytest .repo_template/tests -q -m contract` → 147 passed，367 deselected。
- 危险模式扫描：新增用例只用真实 `/bin/sleep` + 真实 `MoleBridge`，无 `rm`/`FileManager.remove`、无网络、无越界写、无阻塞主线程 `sleep`（轮询用 `Task.sleep`）。唯一危险模式是 `waitUntilBusy` 以 `XCTSkip` 处理前置条件失败（f002），会把失败降级为跳过。
- 红灯归属：anchor `156c58d` 下 `git ls-tree` 无 `tests/unit/CommandConcurrencyTests.swift`、无 `src/zmole/App/MoleCommandLanes.swift`，anchor 的 `AppDependencies` 用单一 `commandBridge` 驱动全部一次性命令（`AppDependencies.swift:322-357`）。5 条用例在 anchor 因**文件缺失/编译失败**而红，而非因行为缺失而红——见 f001 对红灯光照强度的说明。

## Findings

### t025_test_f001 - important - AC-001/AC-002 的用例不判别本次改动，属跨层代理断言，装配别名回归不会被捕获

- 严重度：important
- 锚点：`tests/unit/CommandConcurrencyTests.swift:13-30`（`testIndependentBridgesDoNotShareBusy`）、`:45-58`（`testActiveStreamDoesNotBlockAnotherLane`）、`:6-11`（`testCommandBridgesAreDistinct`）；被测改动 `src/zmole/App/AppDependencies.swift:341-361`、`src/zmole/App/MoleCommandLanes.swift:50-59`
- 问题：本次任务改变的是**装配层**——把原本共用一条 `MoleBridge` 的一次性命令拆到 9 条 lane。但新用例只在**临时自建的两个 `MoleBridge` 实例**上验证「互不 busy」。`MoleBridge.isBusy` 是 actor 实例的私有存储属性（`MoleBridge.swift:52,66`），两个不同实例天然不共享——该断言按构造近乎恒真，且对 anchor 代码同样成立（若把用例拷到 anchor 上跑，同样绿）。因此这两条用例对「App 是否真的按类型拆了通道」零判别力：若日后把 `analyze`/`history`（或 `statusStream`/`statusCommand`）都接到同一个 bridge，`AppDependencies` 出现别名，AC-001/AC-002 会在真机复现，而本测试不会变红。全仓 grep 确认无任何用例断言 `MoleCommandLanes`/`AppDependencies.lanes` 的 lane 分配（`ZmoleTests` 只经 `--demo` 走 `.demo(...)`，而 demo 把所有 lane 别名为同一 `process`，恰好是反例）。`testCommandBridgesAreDistinct` 只覆盖了工厂返回不同实例，未覆盖「不同消费者拿到不同实例」。
- 建议：按 spec 可测试性声明的原意（注入假 `MoleProcessControlling`/`MoleStreaming`）为 `MoleCommandLanes` / `AppDependencies` 的装配加一条断言：用可阻塞的假 process 让 lane A 挂起，断言 lane B 的 `run`/`stream` 不被 `busy` 拒绝；并断言只读消费者各自的 `ObjectIdentifier` 互不相同（能直接卡住别名回归）。若因需真实 bundle 无法测 `AppDependencies`，至少对 `MoleCommandLanes` 加一个「同一实例的多个只读消费者映射到不同 bridge」的构造级断言。

### t025_test_f002 - minor - `waitUntilBusy` 以 `XCTSkip` 兜底，busy 语义回归会把 3 条用例静默跳过而非变红

- 严重度：minor
- 锚点：`tests/unit/CommandConcurrencyTests.swift:67-73`（尤其 `:72`），消费点 `:19`、`:35`、`:52`
- 问题：`waitUntilBusy` 5s 轮询不到 `isBusy` 时 `throw XCTSkip`。若 `MoleBridge` 的 busy 语义被破坏（例如 `activeRunner` 被过早清空、`isBusy` 恒 `false`），`testSameBridgeRejectsConcurrentRun` 的 `.busy` 拒绝断言、以及另两条并发断言都会以**跳过**收场；CI 通常把 skipped 计为未失败，等于 fail-open。当前时序是确定的（`sleep 3` vs 5s 轮询），实际很难触发，但正是「busy 机制回归」时它才会触发——恰是最需要红灯的时候。
- 建议：把前置失败改为 `XCTFail("bridge never became busy")` + 抛出错误（或 `XCTAssertTrue(await bridge.isBusy)` 轮询失败即断言失败），使前置不满足时用例变红而非跳过。

### t025_test_f003 - minor - AC-003 仅复测单例 `OperationCoordinator` 租约，与既有用例重复，未覆盖跨 lane 写入

- 严重度：minor
- 锚点：`tests/unit/CommandConcurrencyTests.swift:60-65`；既有近似用例 `tests/unit/OperationSessionTests.swift:52-66`（`testCoordinatorSerializesWritesAndInvalidatesPreviews`）、`tests/unit/WhitelistOperationTests.swift:6-30`
- 问题：本次改动的核心风险是——写入命令从「共用一条 bridge 由 bridge busy 串行」变成「各自独立 bridge，串行完全依赖 `OperationCoordinator` 租约」。新用例只对裸 `OperationCoordinator` 断言第二次 `acquire` 返回 `nil`，与既有 `testCoordinatorSerializesWritesAndInvalidatesPreviews` 近乎等价，属对未改动组件的重复断言；没有任何用例构造**两个持有不同 bridge、共享同一 coordinator 的写入 VM**并发提交，断言只有一次 spawn（`Uninstall/Optimize/Purge` 的 busy 用例都各自新建独立 coordinator）。若某个写入 VM 忘记取得/持有租约，现有测试集不会变红。
- 建议：加一条跨 lane 用例：同一 `OperationCoordinator`，两个写入 VM（如 clean + uninstall）各持独立假 process，让第一个阻塞持租约，断言第二个的执行被拒（busy）且其假 process 的 `run` 调用数为 0。

### t025_test_f004 - minor - 声明「假 process/streaming + coordinator spy」，实现却用真实 `/bin/sleep`，声明与实现不一致

- 严重度：minor
- 锚点：`spec.md:45`（可测试性声明）、`spec.md:59`（测试策略）；`tests/unit/CommandConcurrencyTests.swift:14-16,33,47-48`
- 问题：spec 声明「注入可控阻塞的假 process / streaming 与 coordinator spy 自动断言并发与互斥」，实际用例用真实 `MoleBridge(executableURL: URL(fileURLWithPath: "/bin/sleep"))` 起真进程，既无假 `MoleProcessControlling`/`MoleStreaming`，也无 coordinator spy。真实并发作为机制证明本身不弱，但它（a）引入外部进程与时序依赖，（b）与 f001 同因——绕开了 lane 装配，无法替代声明中设想的注入式验证。声明与实现的口径应对齐。
- 建议：保留真 bridge 的机制用例（可），另按声明补注入式装配用例；或把 spec 可测试性声明改为与实际一致（真 bridge 机制 + 待补 lane 装配断言）。

## 结论

### AC 覆盖

|AC|用例|判定|
|---|---|---|
|AC-001|`testIndependentBridgesDoNotShareBusy` + `testCommandBridgesAreDistinct`|部分充分：证明两个独立 bridge 互不 busy、工厂产出不同实例；但未触达 `MoleCommandLanes`/`AppDependencies` 装配，两条 bridge 独立近乎恒真、对 anchor 逻辑同样绿，装配别名回归不捕获（见 f001）|
|AC-002|`testActiveStreamDoesNotBlockAnotherLane`|部分充分：stream 与 run 分属不同 bridge 时互不 busy；未使用 `lanes.statusStream`/`statusCommand`，装配回归不捕获（见 f001）|
|AC-003|`testWriteLeaseIsMutuallyExclusiveAcrossOperations`|部分充分：coordinator 租约互斥已断言；但仅复测未改动组件、与既有用例重复，缺跨 lane 写入 VM 的并发排除（见 f003）|
|AC-004|既有 `testCleanDuplicateExecutionCreatesOneProcess`、`testUninstallBusyExecutionCannotStartTwiceAndCanCancel`、`testOptimizeBusy...`、`testPurgeBusy...`、`testBusyCoordinatorPreventsWhitelistWrite`|充分：本改动未触及各页重复提交守卫，行为不变且单次 spawn 已有断言；依赖既有用例可接受|

- 本轮新发现：4 条（0 critical / 1 important / 3 minor）。
- 红灯光照：门禁全绿（183 / 147），无失败测试可归因；但新 5 例在 anchor 的红仅为「测试/SUT 文件缺失→编译失败」，`testIndependentBridgesDoNotShareBusy`/`testSameBridgeRejectsConcurrentRun` 断言的 busy 独立性在 anchor 代码上本已成立——行为级红灯光照未建立，与 f001 同源。
- 未进表提示：`--demo` 装配（`MoleCommandLanes.demo`）把所有 lane 别名为同一 `process`，demo 下只读命令仍会互抢 busy；spec 未把 demo 纳入范围，不计缺口，但若 demo 用于并发演示需另行说明。
- 总体判断：断言非自指、夹具与信号独立，AC-004 覆盖扎实；但 AC-001/AC-002 的用例停留在「两个实例天然独立」的跨层代理层面，不判别本次装配改动（f001, important），叠加 `XCTSkip` fail-open（f002）与 AC-003 未覆盖跨 lane 写入（f003），测试可信度未达标。important 未解决，不得 PASS。

verdict: FAIL

______________________________________________________________________

## Round 2 (2026-10-16T21:50:37+08:00)

### 复核范围

- 重跑 `git -C '/Users/karson/kar/code/zmole_t025' diff 156c58d3f779f9e3562e1f727c0fe1e7c9d50127`：`tests/unit/CommandConcurrencyTests.swift` 74 → 154 行（+80），新增 `BlockingProcessSpy`（actor）。`src/zmole/App/`、`project.pbxproj`、`architecture.md` 与 round 1 一致。生产侧无新逻辑，仅测试增强。
- 门禁：`xcodebuild test -scheme Zmole -destination 'platform=macOS'` → **184 passed，0 failures**；`CommandConcurrencyTests` 6 例全绿；`pytest .repo_template/tests -q -m contract` → 147 passed，367 deselected。
- 危险模式扫描：`XCTSkip` 已移除，`waitUntilBusy` 改为 `XCTFail`（`:119`）。新增 `BlockingProcessSpy` 仅用 continuation 挂起，无真实 I/O。AC-001/002 仍用真实 `/bin/sleep`（机制证明），AC-003 用假 process。无删除/网络/越界写/主线程阻塞。未见新的危险模式。

### 处置确认

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t025_test_f001|important|已修|新增 `testAppDependenciesWiresDistinctLanes` 直接断言**生产** `AppDependencies.lanes` 的 9 条一次性 lane 两两不同且 `estimate != analyze`；`testBusyReadLaneDoesNotBlockAnotherReadLane` 经 `MoleCommandLanes` 容器驱动 `analyze` vs `history`。装配别名回归（把两条只读 lane 指向同一 bridge）现在必然变红——见甄别度复核|tests/unit/CommandConcurrencyTests.swift:15-32,35-50|
|t025_test_f002|minor|已修|`waitUntilBusy` 轮询耗尽改为 `XCTFail("bridge never became busy")`，前置不满足时用例变红而非静默跳过，fail-open 消除|tests/unit/CommandConcurrencyTests.swift:114-120|
|t025_test_f003|minor|已修|新增 `testTwoWriteViewModelsCannotRunConcurrently`：`OptimizeViewModel` 在 lane A 阻塞持租约，`PurgeViewModel`（不同 lane、独立假 process）preview 被拒为 `operation.error.busy` 且 `!isPreviewing`；释放后 optimize `canConfirm`。跨 lane 写入互斥被锁定|tests/unit/CommandConcurrencyTests.swift:67-84|
|t025_test_f004|minor|撤回|AC-003 改用假 `BlockingProcessSpy`；AC-001/002 保留真实 `MoleBridge`+`/bin/sleep` 以证明 lane 级真实并发，比假 process 更强。spec 措辞「假 process/streaming」与实际略有不符属文档细节，非门禁缺口，不再列为遗留|tests/unit/CommandConcurrencyTests.swift:6,101-112,123-154|

### 新增 finding

### t025_test_f005 - minor - 生产 lane 唯一性断言未纳入两条流 lane（`statusStream`/`cleanStream`），AC-002 的装配别名仍无断言

- 严重度：minor
- 锚点：`tests/unit/CommandConcurrencyTests.swift:15-32`（唯一性断言只列 9 条一次性 lane）与 `:53-64`（AC-002 用例走自建 `makeSleepLanes()` 而非生产 `AppDependencies`）
- 问题：`testAppDependenciesWiresDistinctLanes` 的 identity 集合只含 9 条一次性 lane，未纳入 `statusStream`/`cleanStream`。生产 `AppDependencies` 里 `statusStream` 与 `statusCommand` 是分别 `try? MoleBridge()` 的两条通道，AC-002 关注的正是「status --watch 流 vs 只读命令 lane 不同」。若日后回归把 `streamBridge` 别名到 `bridges[4]`（类型上 `MoleBridge` 同时满足 `MoleStreaming` 与 `MoleProcessControlling`，可编译通过），`testAppDependenciesWiresDistinctLanes` 与用自建容器的 `testActiveStatusStreamDoesNotBlockReadLane` 都不会变红。风险低（现有代码分别构造），故 minor。
- 建议：把 `dependencies.lanes.statusStream` 与 `dependencies.lanes.statusCommand`（及 `cleanStream`/`cleanCommand`）一并纳入 identity 断言，或让 AC-002 用例直接使用生产 `AppDependencies.lanes` 而非 `makeSleepLanes()`。

### 甄别度复核（对 anchor）

- `testAppDependenciesWiresDistinctLanes` 具判别力：anchor `AppDependencies` 用单一 `commandBridge` 驱动全部一次性命令（`AppDependencies.swift:322-357`），把该断言搬回 anchor 场景，9 个只读消费者会得到同一实例 → `Set(identities).count == 1 != 9`，必红。这正是本次改动的契约。
- `testBusyReadLaneDoesNotBlockAnotherReadLane`/`testActiveStatusStreamDoesNotBlockReadLane` 经 `MoleCommandLanes` 容器取 lane（该类型 anchor 不存在）；配合上条，断言不再停留于「两个任意实例天然独立」的恒真层面。
- `testTwoWriteViewModelsCannotRunConcurrently` 独立：断言取自生产 VM 的状态键 `operation.error.busy` 与 `isPreviewing`，非自指；若写入 VM 不再取得/持有 `OperationCoordinator` 租约即变红。
- 结论：AC-001/AC-002 现在有可达装配层的判别断言；AC-003 覆盖跨 lane 写入互斥。红灯光照由「仅文件缺失」升级为「缺装配/缺租约即红」。

### AC 覆盖（Round 2）

|AC|用例|判定|
|---|---|---|
|AC-001|`testAppDependenciesWiresDistinctLanes` + `testBusyReadLaneDoesNotBlockAnotherReadLane`|充分：生产 9 lane 两两不同 + 容器内 analyze 挂起时 history 不 busy 且成功 run|
|AC-002|`testActiveStatusStreamDoesNotBlockReadLane`|部分充分：机制充分（stream 与 run 分属不同 bridge 互不 busy）；生产 `statusStream` 唯一性未纳入断言（见 f005，minor）|
|AC-003|`testTwoWriteViewModelsCannotRunConcurrently` + `testWriteLeaseIsMutuallyExclusiveAcrossOperations`|充分：跨 lane 写入 VM 互斥（busy 状态键）+ 裸租约互斥|
|AC-004|既有 `testCleanDuplicateExecutionCreatesOneProcess`、`testUninstallBusy...`、`testOptimizeBusy...`、`testPurgeBusy...`、`testBusyCoordinatorPreventsWhitelistWrite` + `testSameBridgeRejectsConcurrentRun`|充分：行为未改，单次 spawn / 同 lane 拒绝 busy 均有断言|

- 本轮新发现：1 条（0 critical / 0 important / 1 minor）。
- 处置：f001 已修、f002 已修、f003 已修、f004 撤回；无遗留 critical/important。
- 未进表提示：`--demo` 装配仍把所有 lane 别名为同一 `process`（`MoleCommandLanes.demo`），demo 下只读命令仍会互抢 busy；非 AC 范围，不计缺口。
- 总体判断：round 1 的 important 缺口（AC-001/002 不判别装配改动）已由生产级 lane 唯一性断言闭合，`XCTSkip` fail-open 与 AC-003 跨 lane 覆盖同步补齐，测试现对 anchor 具备行为级判别力。残余 f005 为 minor（AC-002 流 lane 唯一性未纳入断言），不阻门禁。测试可信度达标。

reviewed_scope: 6d211272f4bcb643

verdict: PASS
