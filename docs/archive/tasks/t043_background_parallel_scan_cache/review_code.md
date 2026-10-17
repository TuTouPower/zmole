# Task review t043（reviewer_focus: 代码）

- task：`t043_background_parallel_scan_cache`
- spec：`docs/tasks/t043_background_parallel_scan_cache/spec.md`
- diff_anchor：`a7dc728648e71029b450d300ed12b734bbff828d`
- target：`git -C '/Users/karson/kar/code/zmole_t043' diff a7dc728648e71029b450d300ed12b734bbff828d`
- round：1
- reviewed_at：2026-10-17T18:41:00+08:00

reviewed_scope: 1a8284d643090e40

## Findings

### t043_code_f001 - `cancelAndWait` 先等通道取消再置任务取消位，取消窗口内完成的后台扫描仍会回写结果

- 严重度：minor
- 锚点：行为缺陷 + 并发时序：后台扫描恰在用户接管该项的瞬间完成时，`userDidRescan*` 已丢弃的结果会被重新写回（AC-002/AC-005 的窄窗口竞态，非确定性）
- 位置：`src/zmole/Features/Operations/BackgroundScanService.swift:175`（`cancelAndWait`，与 `:278` 的 `guard !Task.isCancelled` 配合失效）
- 问题：`cancelAndWait` 的顺序是 `await cancelLane(item)` → `task.cancel()`。整个 `await cancelLane` 取消窗口内任务的取消位仍为 false，而 `run` 落盘前唯一防护 `guard !Task.isCancelled`（:278）在 `payload` 返回之后才检查。若后台进程恰在取消发起前已结束（`MoleBridge.cancel` 见 runner 已 finished 即返回，MoleBridge.swift:147），`run` 可在 `userDidRescan(.clean)` / `userDidRescanAndWaitForTermination(.clean)` 移除结果之后继续执行 `results[item] = ...` / `cache.save`（:279-282），把刚丢弃的结果回写：clean 项日后可能被 `adoptPrewarmPreviewIfAvailable` 采纳为陈旧预览（确认时被 `verifyUnchanged` 拒绝，不会误执行）；若该进程以非零退出码结束，还会给已被用户接管的项留下 `failedItems` 标记与 1 小时重试退避（:223、:287），期间该后台项不刷新。`task.cancel()` 放在 `cancelLane` 之后，使 :278 的防护在此竞态下失效。
- 建议：把 `task.cancel()` 提到 `await cancelLane(item)` 之前（或在落盘前复核该 task 仍与 `tasks[item]` 同一实例），使取消位在取消窗口内即为 true。

## 结论

- 前轮 finding 复核：Round 1，无前轮。
- 本轮新发现：1 条（minor）。
- 未进表的提示：
  - 文件过大：`tests/unit/BackgroundScanTests.swift` 736 行（测试阈值 ≥600 → 建议拆分；未达 1200）。新建时即超阈值，按降级规则只在此提示，不进 finding 表。
  - 复杂度：`CleanViewModel.confirmExecution`（约 CC 11）、`MaintenanceViewModel.previewMaintenance`、`UninstallViewModel.confirmExecution`（约 CC 10-12）为既有长函数，本 task 仅在其中各加 1 个 await 或做参数重命名，未新增分支/嵌套，暂不进 finding。
  - 零引用方法：`BackgroundScanService.stop()`（:213）全仓无调用方；AC-010 由 `installShutdownHandler()` 对 `allProcessLanes`/`allStreams`（已含扫描通道）逐通道 cancel 覆盖，退出前停周期任务的接线缺失，属可选清理。
  - 契约区 drift 核对：AC-001 措辞由「五个只读扫描自动开始」改为「未命中 24 小时缓存的只读扫描项自动开始」。变更后与已获批范围区「启动时先加载缓存；每 24 小时刷新」及 AC-003/AC-004 一致（原文与 AC-004 互斥），判定为 spec 同步修正，不作为 blocking finding。
- 总体判断：`git status --porcelain` 无未跟踪交付文件，diff 覆盖全部交付；实现完整覆盖 11 条 AC（并行启动与只读 argv 白名单、clean 互斥并等待进程终止、缓存落盘与重启读取、24 小时时效、运行中请求复用、写入失效重扫与确认保护、失败保留并标记、FDA 延后补跑、退出取消通道），独立跑 15 条新测试与全量 294 条测试全绿；仅 1 条 minor 时序改进，无未解决 critical/important。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001 re_verified：独立运行 `xcodebuild test ... -only-testing:ZmoleTests/BackgroundScanTests`，`testAllItemsStartInParallelAndUseReadOnlyCommands` 通过（4 个进程项同时 blocked、`runningItems.count == 4`）；代码 `init` 的 `refreshIfDue()` 逐项起任务。
- AC-002 re_verified：`testUserCleanScanCancelsAndWaitsForBackgroundClean`、`testCleanRequestDefersWhileWriteLeaseIsHeld` 通过；`CleanViewModel.swift:90`/`:226` 双路径先 `userDidRescanAndWaitForTermination(.clean)` 再触碰文件；`MoleBridge.cancel()` 等待 runner 终止（MoleBridge.swift:147-153）。
- AC-003 re_verified：`testCacheRoundTripAndFreshResultsSkipScanning`（save/load 等值、fresh 缓存 0 次命令调用）+ 页面采纳测试断言 `listCapturedAt`/`previewCapturedAt`；`BackgroundScanCache.save/load` 代码核对。
- AC-004 re_verified：`testOnlyStaleResultsAreRefreshed`（仅 stale 项重扫、fresh 不动）通过；`shouldRefresh` 24 小时分支代码核对。
- AC-005 re_verified：`testRefreshWhileRunningReusesTheInFlightScan` 通过（运行中 request 不产生第二进程；完成后可再起）；`request` 的 `tasks[item] == nil` 守卫代码核对。
- AC-006 re_verified：`testInvalidationClearsResultsAndRescansEverything`（失效后 5 项全部重扫）、`testCleanPageAdoptsBackgroundResultAndProtectsTheConfirmation`（confirming 期间新结果不替换）通过。
- AC-007 re_verified：`testFailingItemKeepsPreviousResultAndRetriesLater` 通过（保留旧结果、`failedItems` 标记、其他项不受影响、2 小时后重试）。
- AC-008 re_verified：`testAllItemsStartInParallelAndUseReadOnlyCommands` 的 argv 白名单与 banned 集合断言通过；`payload(for:)` 只 spawn `uninstall --list-stream`、`installer --list-json` 与三个 `--dry-run`。
- AC-009 re_verified：`testMissingFullDiskAccessDefersInstallerUntilGranted` 通过；`request(.installerList)` 的 `diskAccessGranted` 门槛与 `accessMonitor.$isGranted.dropFirst()` 补跑订阅（AppDependencies.swift:252-257）代码核对。
- AC-010 re_verified：`testShutdownCoversBackgroundScanLanes` 通过（四进程通道 + uninstall 流均在 shutdown 集合）；`installShutdownHandler` 对 `allProcessLanes`/`allStreams` 逐通道 cancel。
- AC-011 re_verified：`testCorruptOrOldSchemaCacheIsIgnored` 通过；`load()` 的 `try?` + `schemaVersion` 过滤使损坏/旧 schema 按无缓存处理并由启动 `refreshIfDue()` 触发重扫。
- 另跑全量套件（`xcodebuild test -scheme Zmole -destination 'platform=macOS'`）：294 tests，0 failures，覆盖 15 条 `BackgroundScanTests`。
- coverage = 11/11（trust_prior 0 项）

verdict: PASS

## Round 2 (2026-10-17T19:02:41+08:00)

reviewed_scope: 826705ec0043beef

### 前轮 finding 复核

- `t043_code_f001`（minor：`cancelAndWait` 先等通道再置取消位，取消窗口内完成的后台扫描会回写结果）：**已消除**。`src/zmole/Features/Operations/BackgroundScanService.swift:179` 现在先 `task.cancel()`，其后才是 `await cancelLane(item)`（:180）与 `await task.value`（:181）；`run` 落盘前的 `guard !Task.isCancelled`（:271）在整段取消窗口内即为 true，窗口内完成的扫描不会再写入 `results`/缓存。Round 1 提示的零引用 `stop()` 已删除（文件内已无 `func stop`，原 :213 位置现为 `// MARK: - Execution`）。

### 本轮新发现

#### t043_code_f002 - `request` 不检查 `deferredClean`，周期 tick 可在「用户接管间隙」启动第二个 clean 写进程

- 严重度：minor
- 锚点：AC-002「clean 扫描与 clean 用户刷新/执行互斥……观测不到两个进程同时写 `clean-list.txt`」；并发时序，窄窗口、非确定性
- 位置：`src/zmole/Features/Operations/BackgroundScanService.swift:141-143`（注释声称的防护）、`:166-169`（`request` 只查 `isCleanBusy`）、`:236-246`（周期 tick）
- 问题：`previewClean` 在 `preview == nil` 时（首次打开页面且后台 clean 尚无结果、或上次预览失败后）先 `await userDidRescanAndWaitForTermination(.clean)`（CleanViewModel.swift:90）；该路径设置 `deferredClean = true`（:144），但 `request` 对 clean 只检查 `isCleanBusy`（:166），不看 `deferredClean`，:141-143 注释声称「周期 tick 无法在取消与用户取租约之间的间隙启动竞争写者」并不成立。当用户接管时确有后台 clean 任务被取消时，旧任务退出（`run` 的 defer 清掉 `tasks[.clean]`，:265-268）到 `previewClean` 恢复执行 `leaseCoordinator.acquire(.clean)` 之间存在主 actor 的 job 边界；此时 tick（:243）或其他路径的 `request(.clean)` 命中 `refreshIfDue` → `shouldRefresh(.clean)`（结果已被移除，返回 true，:215-226）→ `request(.clean)`：`tasks` 为空且 `isCleanBusy` 尚未置位（preview/确认/isPreviewing/isExecuting/租约均未进入）→ 启动一个新的后台 `clean --dry-run`。此后用户预览开始，两侧都 `begin()` 并写同一 `clean-list.txt`：用户预览可能读到后台进程写出的内容，或后台 `begin()` 删除用户刚写出的文件使 `read` 抛 `missingFile`（页面显示「本次 clean 预览没有写出列表文件」）。
- 建议：让 `request` 参与 `deferredClean` 判定，例如 `if item == .clean, deferredClean || isCleanBusy { return }`，由 `noteActivityChanged` 作为解除点（该函数在 `!isCleanBusy` 时清标记并重启，用户预览/执行结束后仍能恢复）；或引入显式「用户接管 clean」标志，在 `userDidRescanAndWaitForTermination` 入口置位、用户活动结束时清除。

#### t043_code_f003 - `cancelAndWait` 收尾无条件清 `tasks[item]`，可覆盖间隙中新注册的后台任务

- 严重度：minor
- 锚点：AC-005「同一项已有扫描运行时，刷新请求不产生第二个同类进程」；并发时序，窄窗口、非确定性
- 位置：`src/zmole/Features/Operations/BackgroundScanService.swift:176-182`（:182 `tasks[item] = nil`）
- 问题：`cancelAndWait` 捕获 `task` 后，在 `await task.value` 之后无条件把 `tasks[item]` 置 nil。被取消任务退出时其 defer 已经清过一次（:265-268），在 `task.value` 恢复前的主 actor job 边界内，若 tick/`noteActivityChanged` 调用 `request(item)`（彼时 `tasks[item] == nil`、`results` 已由 `userDidRescan*` 移除、`shouldRefresh` 返回 true），会注册新任务 T2；随后 `cancelAndWait` 恢复并把 `tasks[item]` 置 nil，T2 成为未登记任务：(a) 后续 `request(item)` 不再被 T2 阻挡，可再起同项进程（AC-005 出现两个同类进程）；(b) `userDidRescan*` 的 `guard let task = tasks[item]` 直接返回，无法取消 T2，T2 完成后仍写入 `results`/缓存，把已被用户接管的结果重新覆盖（与 Round 1 f001 同类回写路径）。`invalidateAll`（:285-294）逐项调用 `cancelAndWait`，命中面相同。
- 建议：清除前复核身份（例如为每个注册任务配 UUID，仅当 `tasks[item]` 仍是本次捕获实例时置 nil）；或删掉 :182，交由 `run` 的 defer 统一清理（defer 在任务体内同步执行，无插入点，安全）。

### 结论

- 前轮 finding 复核：`t043_code_f001` 以代码核实已消除；Round-2 改动仅 `cancelAndWait` 顺序调整与 `stop()` 删除，未见其他行为变化。
- 本轮新发现：2 条（均 minor，窄窗口并发时序；f002/f003 可同一次事件触发）。
- 未进表的提示：
  - 文件过大：`tests/unit/BackgroundScanTests.swift` 807 行（测试阈值 ≥600，本 task 新建并净增；未达 1200，按降级规则仅提示）。
  - 复杂度：`CleanViewModel.confirmExecution` 约 CC 11（既有长函数，本 task 仅加 1 个 await，无新分支）；`BackgroundScanService` 各函数 CC 均 < 10。
  - 只写属性：`BackgroundScanService.periodicTask`（:90、:237）在 `stop()` 删除后无任何读取；循环仅在弱引用失效时退出，属可选清理。
  - 命名遗留：界面复用旧 key `prewarm.scan_time`（CleanView/UninstallView 等 5 处），页面文案改造属 t044 非范围。
  - 契约区 drift 核对：AC-001 措辞（未命中 24 小时缓存的项才启动）与 AC-010 可测试性声明两处变更，与已批准范围区「启动先加载缓存、每 24 小时刷新」及 `BackgroundScanTests`/`CommandConcurrencyTests` 的实际验证方式一致，判为 spec 同步，不作为 finding。
- 七视角扫描：安全（argv 固定白名单、无外部输入拼接、缓存仅写应用支持目录）未命中；契约·Breaking（更名与协议仅内部、缓存带 schemaVersion、CLI argv 未改）未命中；性能·资源（每项独立通道并行、无循环内查询、主线程小 JSON 读写可接受）未命中；架构·可维护性（服务/协议/通道边界清晰）未命中；健壮性·可观测（失败写入 `failedItems` 且保留旧结果，无吞错）未命中；测试·文档（spec/blueprint 同步，测试细节由 test reviewer 另审）未命中；正确性视角即 f002/f003。
- 总体判断：Round 1 的 minor 已修，实现完整覆盖 11 条 AC；本轮仅 2 条窄窗口时序 minor，无未解决 critical/important。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001 re_verified：独立重跑 `xcodebuild test ... -only-testing:ZmoleTests/BackgroundScanTests`，`testAllItemsStartInParallelAndUseReadOnlyCommands` 通过（4 个进程项同时 blocked、`runningItems.count == 4`）；`init` 的 `refreshIfDue()` 逐项起任务，未命中缓存的项才启动。
- AC-002 re_verified：`testUserCleanScanCancelsAndWaitsForBackgroundClean`、`testCleanRequestDefersWhileWriteLeaseIsHeld` 通过；`CleanViewModel.swift:90`/`:226` 双路径先 `userDidRescanAndWaitForTermination(.clean)` 再触碰文件；`MoleBridge.cancel()` 等待 runner 终止（MoleBridge.swift:147-153）。
- AC-003 re_verified：`testCacheRoundTripAndFreshResultsSkipScanning`（save/load 等值、fresh 缓存 0 次命令调用）通过 + 页面采纳测试断言 `listCapturedAt`/`previewCapturedAt`；`BackgroundScanCache.save/load` 代码核对。
- AC-004 re_verified：`testOnlyStaleResultsAreRefreshed`、`testPeriodicRefreshRescansStaleResults` 通过（仅 stale 项重扫、推进时钟跨 24 小时后重扫）；`shouldRefresh` 分支代码核对。
- AC-005 re_verified：`testRefreshWhileRunningReusesTheInFlightScan` 通过（运行中 request 不产生第二进程、完成后可再起）；`request` 的 `tasks[item] == nil` 守卫代码核对（收尾竞态见 f003）。
- AC-006 re_verified：`testInvalidationClearsResultsAndRescansEverything`（失效后 5 项全部重扫）、`testCleanPageAdoptsBackgroundResultAndProtectsTheConfirmation`（confirming 期间新结果不替换）通过。
- AC-007 re_verified：`testFailingItemKeepsPreviousResultAndRetriesLater` 通过（保留旧结果、`failedItems` 标记、其他项不受影响、2 小时后重试）。
- AC-008 re_verified：`testAllItemsStartInParallelAndUseReadOnlyCommands` 的 argv 白名单断言通过；`payload(for:)` 只 spawn `uninstall --list-stream`、`installer --list-json` 与三个 `--dry-run`。
- AC-009 re_verified：`testMissingFullDiskAccessDefersInstallerUntilGranted` 通过；`request(.installerList)` 的 `diskAccessGranted` 门槛与 `accessMonitor.$isGranted.dropFirst()` 补跑订阅（AppDependencies.swift:252-257）代码核对。
- AC-010 re_verified：`testShutdownCoversBackgroundScanLanes`、`testShutdownCancelsInFlightBackgroundScanProcesses` 通过（四个后台进程通道 + uninstall 流均在取消集合，且在途进程收到 `.cancelled`）；`installShutdownHandler` 对 `allProcessLanes`/`allStreams` 逐通道 cancel 并限时等待 2 秒。
- AC-011 re_verified：`testCorruptOrOldSchemaCacheIsIgnored` 通过；`load()` 的 `try?` + `schemaVersion` 过滤使损坏/旧 schema 按无缓存处理并由启动 `refreshIfDue()` 触发重扫。
- 另跑全量套件（`xcodebuild test -scheme Zmole -destination 'platform=macOS'`）：296 tests，0 failures；两轮间新增的 `testShutdownCancelsInFlightBackgroundScanProcesses` 含在内。
- coverage = 11/11（trust_prior 0 项）

verdict: PASS

## Round 3 (2026-10-17T19:10:30+08:00)

reviewed_scope: 17abd136a2cec471

### 前轮 finding 复核

- `t043_code_f002`（minor：`request` 不检查 `deferredClean`，周期 tick 可在用户接管间隙启动第二个 clean 写进程）：**已消除**。`request` 的 clean 分支现在先查 `isCleanBusy`（`BackgroundScanService.swift:167-170`），再查 `deferredClean`（:174）；`deferredClean` 由 `userDidRescanAndWaitForTermination`/`userDidRescan` 在取消动作之前同步置位（:144、:128），唯一清除点是 `noteActivityChanged` 且要求 `!isCleanBusy`（:205-209）。周期 tick 经 `refreshIfDue`→`request(.clean)` 在接管间隙一律被 :174 拦截，不再产生第二个写者；用户预览/确认/执行期间 `isCleanBusy` 为真、不解除，活动结束后由 `ActivityCoalescer`（AppDependencies.swift:294-311）触发解除并补跑。
- `t043_code_f003`（minor：`cancelAndWait` 收尾无条件清 `tasks[item]`，可覆盖间隙中新注册的后台任务）：**已消除**。`cancelAndWait`（:181-190）已不再写 `tasks`；注册表清理唯一归属 `run` 的 defer（:272-275），defer 在任务体返回前同步执行，`await task.value` 恢复不早于 defer，不会再覆盖间隙中注册的新任务；:188-189 注释与实现一致，`request:159` 守卫保证新任务只在注册表为空时注册，无「已完成任务仍占位」或「新任务被清空」的路径。

### 本轮新发现

本轮 0 条。修复引入路径逐项核对：`request` 新增早退不饿死 clean（置位方 CleanViewModel.swift:90/:226 后续必有 published 变更触发解除）；`cancelAndWait` 移除手动清理不影响 `invalidateAll`/`userDidRescan*` 既有语义（注册与清理单一归属 `request`/`run`）。

### 结论

- 前轮 finding 复核：f002、f003 均以当前工作区代码核实已消除（未采信处置表；task.md 处置表本轮仍为空）。
- 本轮新发现：0 条。
- 未进表的提示：
  - 残余理论窗口（低置信度，未达 finding 门槛）：`noteActivityChanged`（:205-209）在 `deferredClean && !isCleanBusy` 时会清标记并起扫描；理论上若它恰在「被取消任务终止后、用户取租约前」的间隙被触发（coalescer 或 FDA 授权），仍可启动竞争写者。本仓未找到该间隙内可产生 `cleanViewModel` 发布的现实触发源（`previewClean` 在等待取消期间不发布 VM 状态；点击前的发布风暴落在旧任务仍注册的窗口，被 :159 的 `tasks[item] == nil` 守卫拦住），故不进 finding 表；若未来在取消等待路径新增 VM 状态发布，应改用显式「用户接管中」标志或由 VM 在活动真正开始时确认接管。
  - 文件过大：`tests/unit/BackgroundScanTests.swift` 807 行（测试阈值 ≥600，未达 1200；本 task 新建并净增，按降级规则仅提示）。
  - 复杂度：`BackgroundScanService` 全部函数 CC < 10；`CleanViewModel.confirmExecution` 约 CC 11 为既有长函数，本轮未新增分支。
  - `periodicTask`（:90、:244）仍只写不读（Round 2 已提示，可选清理）。
  - 契约区 drift 核对：AC-001 措辞（未命中 24 小时缓存的项才启动）与 AC-010 可测试性声明的变更，与已批准范围区及测试实现一致，判为 spec 同步，不作为 finding。
- 七视角扫描（聚焦修复引入面 + 全量 diff 复核）：安全（argv 固定白名单、缓存仅写应用支持目录、无外部输入拼接）未命中；契约·Breaking（更名均内部、缓存带 schemaVersion、CLI argv 未变）未命中；性能·资源（每项独立通道、无循环内查库）未命中；架构·可维护性（注册表单一归属、服务/协议/通道边界清晰）未命中；健壮性·可观测（失败写 `failedItems` 且保留旧结果、无吞错）未命中；测试·文档（spec/blueprint 同步）未命中；正确性即 f002/f003 复核 + 残余理论窗口提示。
- 总体判断：Round 2 的 2 条 minor 均已消除；本轮修复未引入可观测新问题，无未解决 critical/important。
- 系统性 follow-up：无。

### AC 复验方式

- 本轮独立重跑 `xcodegen generate` + `xcodebuild test -scheme Zmole -destination 'platform=macOS' -only-testing:ZmoleTests/BackgroundScanTests`：16/16 通过；随后全量 `xcodebuild test -scheme Zmole -destination 'platform=macOS'`：296/296 通过（0 failures，TEST SUCCEEDED）。Round 2 后仅 `src/zmole/Features/Operations/BackgroundScanService.swift` 有改动（mtime 19:03:22），修复面即 f002/f003。
- AC-001 re_verified：`testAllItemsStartInParallelAndUseReadOnlyCommands` 重跑通过（4 进程项并行、argv 白名单）；`init` 的 `refreshIfDue()` 代码核对。
- AC-002 re_verified：`testUserCleanScanCancelsAndWaitsForBackgroundClean`、`testCleanRequestDefersWhileWriteLeaseIsHeld` 重跑通过；本轮新增核对 `request:166-175` 的 `isCleanBusy`/`deferredClean` 双守卫与 :144 置位先于取消，f002 路径关闭。
- AC-003 re_verified：`testCacheRoundTripAndFreshResultsSkipScanning` 重跑通过；`BackgroundScanCache.save/load` 代码核对。
- AC-004 re_verified：`testOnlyStaleResultsAreRefreshed`、`testPeriodicRefreshRescansStaleResults` 重跑通过；`shouldRefresh` 分支核对。
- AC-005 re_verified：`testRefreshWhileRunningReusesTheInFlightScan` 重跑通过；`request:159` 守卫与 `cancelAndWait:181-190`/`run` defer 单一清理注册表核对，f003 路径关闭。
- AC-006 re_verified：`testInvalidationClearsResultsAndRescansEverything`、`testCleanPageAdoptsBackgroundResultAndProtectsTheConfirmation` 重跑通过。
- AC-007 re_verified：`testFailingItemKeepsPreviousResultAndRetriesLater` 重跑通过。
- AC-008 re_verified：`testAllItemsStartInParallelAndUseReadOnlyCommands` 的 argv 白名单断言重跑通过；`payload(for:)` 仅 spawn 五条只读命令核对。
- AC-009 re_verified：`testMissingFullDiskAccessDefersInstallerUntilGranted` 重跑通过；`request:160-164` 与 `accessMonitor.$isGranted.dropFirst()` 订阅（AppDependencies.swift:252-257）核对。
- AC-010 re_verified：`testShutdownCoversBackgroundScanLanes` 重跑通过（全量套件含 `testShutdownCancelsInFlightBackgroundScanProcesses`）；`installShutdownHandler` 对 `allProcessLanes`/`allStreams` 逐通道 cancel 核对。
- AC-011 re_verified：`testCorruptOrOldSchemaCacheIsIgnored` 重跑通过；`load()` 的 `try?` + `schemaVersion` 整文件校验核对。
- coverage = 11/11（trust_prior 0 项）

verdict: PASS
