# Task review t043（reviewer_focus: 测试）

- task：`t043_background_parallel_scan_cache`
- spec：`docs/tasks/t043_background_parallel_scan_cache/spec.md`
- diff_anchor：`a7dc728648e71029b450d300ed12b734bbff828d`
- target：`git -C '/Users/karson/kar/code/zmole_t043' diff a7dc728648e71029b450d300ed12b734bbff828d`
- round：1
- reviewed_at：2026-10-17T18:40:01+08:00

reviewed_scope: 1a8284d643090e40

## Findings

### t043_test_f001 - AC-002 用例含不可失败的恒真断言，且无法区分「等待终止」

- 严重度：important
- 锚点：危险模式「恒真断言」（最低 important）；AC-002「执行开始前被取消的后台 clean 进程已终止」；`BackgroundScanProviding` 契约「cancel the background run and drop its result so the user's scan becomes authoritative」（`BackgroundScanService.swift:43-45`）与 `docs/specs/clean.md`「后台扫描结果在用户预览启动时被丢弃」。
- 位置：`tests/unit/BackgroundScanTests.swift:47`（断言），用例 `tests/unit/BackgroundScanTests.swift:38-48`，spy `cancel()` 在 `tests/unit/BackgroundScanTests.swift:608-612`
- 问题：用例布置为「空缓存 + clean 首次进程被阻塞」，`results` 只可能在 `run()` 成功后写入，被取消的 run 走 catch 后直接 return（`src/zmole/Features/Operations/BackgroundScanService.swift:283-289`），因此 `service.result(for: .clean)` 整条用例中恒为 nil，第 47 行 `XCTAssertNil(..., "the cancelled background result is dropped")` 不可能失败：删除 `userDidRescanAndWaitForTermination` 里的 `results.removeValue`（`BackgroundScanService.swift:146-148`）用例仍全绿，「取消后丢弃既有结果」在服务侧无其他覆盖（`userDidRescan` 的同语义分支 `BackgroundScanService.swift:130-132` 亦无有效测试）。同一个 spy 的 `cancel()` 同步 resume 阻塞 continuation，被取消的 run 立即结束，用例也无法区分 `cancelAndWait` 是否真的执行 `await task.value`（`BackgroundScanService.swift:175-181`）：删掉 `await task.value` 用例仍全绿，AC-002 明示的「等待进程终止」语义实际未被验证。
- 建议：先向 `BackgroundScanCache` 预置一条 clean 既有结果（或让首个 clean 扫描先完成）再触发用户 rescan，断言结果与 `capturedAt` 被清除；并让 spy 的阻塞 run 仅在显式二次放行（如 `finishCancellation()`）后终止，断言 wait 任务在放行前不完成、放行后才返回。

### t043_test_f002 - AC-010 声明的「取消计数」验证未落实，用例仅断言 lanes 属于取消集合

- 严重度：minor
- 锚点：AC-010；spec 可测试性声明 `spec.md:55`「AC-010 使用可观测的取消计数验证，真实进程退出由现有集成脚本覆盖」。
- 位置：`tests/unit/CommandConcurrencyTests.swift:38-53`
- 问题：用例只把 `scan.installerProcess/clean/optimize/purge` 与 `scan.uninstallStreaming` 的 `ObjectIdentifier` 和 `allProcessLanes`/`allStreams` 做成员比对，从未执行取消、未统计任何 cancel 次数；`installShutdownHandler` 的逐 lane `cancel()` 调用（`src/zmole/App/AppDependencies.swift:270-288`）被移除时用例仍绿。另核实 `tests/integration/` 三个脚本（clean_trash/installer_interface/uninstall_stream）均不含 shutdown/cancel 关键字，「真实进程退出由现有集成脚本覆盖」没有可指认的载体。
- 建议：构造 spy lanes 集合执行一次取消并断言每条 scan lane 的 `cancel` 计数 ≥1（或把 shutdown 取消逻辑抽成可测函数直接驱动）；否则修订 spec 可测试性声明，与成员性验证保持一致。

### t043_test_f003 - AC-004 的运行期定时触发路径无任何测试

- 严重度：minor
- 锚点：AC-004「应用运行期间，缓存超过 24 小时会触发该项自动重扫」。
- 位置：`src/zmole/Features/Operations/BackgroundScanService.swift:243-253`（`startPeriodicRefresh`）；`tests/unit/BackgroundScanTests.swift:361-378`（`makeService` 的 `periodicTick` 参数，无调用点传非默认值）
- 问题：AC-004 用例只验证 `refreshIfDue` 在 init/手动调用时的判定（stale→重扫、fresh→不扫）；没有任何用例驱动 periodic 循环。删除 `startPeriodicRefresh` 并摘掉 init 调用后 15 个用例仍全绿，说明「运行期自动触发重扫」分支零覆盖，为此设计的 `periodicTick` 注入参数从未被使用。
- 建议：补一条 `periodicTick: 0.05` + 可变 `now` 的用例：启动时 fresh 不扫，推进 `now` 超 24h 后等待该项出现第二次进程调用。

## 结论

- 契约区 drift 核对：AC-001 由「五个只读扫描自动开始」改为「未命中 24 小时缓存的只读扫描项自动开始」，与 `task.md` front matter 用户批准 note（「预览改后台扫描；独立项并行；结果落盘；每 24 小时刷新」）及 AC-003/AC-004 自洽，判定为已确认的需求变更，非 blocking。
- 改测方向复核：无。`CommandConcurrencyTests` 的改动全部是扩展（distinctness 追加 scan lanes、新增 shutdown 成员用例、`makeSleepLanes` 补 scan lanes；`AppDependencies(backgroundScanEnabled: false)` 是新增参数以避免测试环境启动真实扫描），没有删除/反转/弱化既有断言；`PrewarmTests` 整体删除属测试策略明文批准（`spec.md:70`），其页面采纳与确认保护用例已逐条等价保留在 `BackgroundScanTests`（uninstall/installers/clean 采纳、确认框保护、optimize/purge 采纳断言与旧文件一致）。
- 本轮新发现：3 条（1 important + 2 minor）。
- 未进表的提示：AC-008 的负向检查是「4 个精确黑名单形态 + 5 条正向包含」，非全量白名单（额外调用如 `["purge"]` 不会失败），满足 AC-008 枚举、与测试策略措辞「断言只读 argv 白名单」有差，可选收紧为「所有记录调用 ∈ 5 条白名单」；AC-003 的「重启后、本次扫描完成前可读上次结果」交错场景未直接构造（现由缓存往返 + fresh 不重扫 + 失败保留间接覆盖）；`CleanViewModel.previewClean/confirmAndRun`、`InstallersViewModel.scan`、`MaintenanceViewModel.previewMaintenance` 对 `userDidRescan*` 的接线调用无测试（服务侧语义已测，调用为直连代码）。其余测试可信度核查通过：spy 均在进程/流系统边界，服务测试组合真实 `BackgroundScanService`/`BackgroundScanCache`/`CleanPreviewStore`/`UninstallListStream`/`InstallerInterface`（含真实 JSON 解析）/`OperationCoordinator`，缓存全部落临时目录，未触碰真实 `~/Library/Application Support`；全量 `xcodebuild test`（294 个用例）与聚焦重跑（23 个用例）均零失败。
- 总体判断：测试结构与隔离总体可信，但 AC-002 用例存在不可失败的恒真断言且不能区分「等待终止」语义，构成 1 条未解决的 important，本轮不通过。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001：re_verified — 重跑 `xcodebuild test -only-testing:ZmoleTests/BackgroundScanTests` 15/15 绿；断言 `probe.max ≥ 2`、`runningItems == 4`、5 条只读 argv 精确匹配。
- AC-002：re_verified — 「用户 rescan 取消并等待」与「写入租约持有期 defer、释放后补跑」两条路径均有用例且重跑绿；判别力缺口见 f001。
- AC-003：re_verified — 临时目录缓存往返与 `results` 全等（含 `capturedAt`）+ fresh 缓存零进程调用。
- AC-004：re_verified — stale 项触发重扫、fresh 项不扫；运行期 periodic 触发缺口见 f003。
- AC-005：re_verified — 运行中刷新请求进程数保持 1，完成后再次请求进程数为 2。
- AC-006：re_verified — `invalidatePreviews()` 后清空并重扫全部 5 项；确认框打开期间新结果不替换（preview 保持相等）。
- AC-007：re_verified — 失败项保留旧候选、进入 `failedItems`，退避 2h 后重试（进程数 2），其他项结果不受影响（并见并行用例全部完成）。
- AC-008：re_verified — 5 条正向 argv 精确断言 + `clean`/`optimize`/`purge --yes`/`uninstall` 四形态黑名单断言；收紧空间见未进表提示。
- AC-009：re_verified — 无 FDA 时 installer 0 调用，授权事件后自动补跑 ≥1。
- AC-010：re_verified — shutdown 集合包含 4 条 scan 进程 lane 与 scan 流 lane，handler 逐 lane cancel（代码查证）；真实进程退出未独立复验，见 f002。
- AC-011：re_verified — 非 JSON 与 `schemaVersion: 0` 缓存均 `load() == [:]`（按无缓存处理）。
- coverage = 11/11

verdict: FAIL

## Round 2 (2026-10-17T18:51:29+08:00)

reviewed_scope: 2de17dbbfd5b148c

### 前轮 finding 复核

- t043_test_f001（important，AC-002 恒真断言/无法区分等待终止）：已消除。`testUserCleanScanCancelsAndWaitsForBackgroundClean`（`tests/unit/BackgroundScanTests.swift:38-67`）先向缓存预置一条 clean 结果并把 clean 首次扫描阻塞（:42-48），取消前断言结果非 nil（:51）、`userDidRescanAndWaitForTermination` 后断言 nil（:59）——删除 `BackgroundScanService.swift:146-148` 的 `results.removeValue` 会直接失败；spy 的 `cancel()` 不再放行阻塞 continuation（:649-653），用例断言 `waitFinished` 在 `finishCancellation()` 前保持 false（:60-61）、放行后为 true（:63-65）——删除 `BackgroundScanService.swift:181` 的 `await task.value` 会失败；磁盘缓存条目清除亦有断言（:66）。本轮独立重跑该用例通过（0.128s）。
- t043_test_f002（minor，AC-010 仅成员断言）：部分消除。成员部分有效——`testShutdownCoversBackgroundScanLanes`（`tests/unit/CommandConcurrencyTests.swift:38-53`）断言 4 条 scan 进程 lane 与 scan 流 lane 位于 `allProcessLanes`/`allStreams` 集合内，删掉 `MoleCommandLanes.swift` 中 scan 段的收集会失败。但新增的「真实进程终止」验证以被容差掩盖的形式弱化（见 f004）；`spec.md:55` 的可测试性声明已改为「通过取消后台扫描通道后 MoleBridge 的忙碌状态与任务退出验证」，该声明当前依据不足。
- t043_test_f003（minor，AC-004 运行期定时路径零覆盖）：已消除。`testPeriodicRefreshRescansStaleResults`（`tests/unit/BackgroundScanTests.swift:145-164`）以 `periodicTick: 0.05` + `MutableClock` 驱动：推进前 0 调用（:157-159），`now` 前移 25h 后等待 optimize 第二次进程调用（:161-162）；删除 `BackgroundScanService.swift:236-246` 的 `startPeriodicRefresh` 或 init 调用后该用例必然超时失败。本轮独立重跑通过（0.264s）。

### t043_test_f004 - AC-010 在途取消用例的 busy 判定被轮询容差掩盖，取消失效/被移除也不会失败

- 严重度：important
- 锚点：危险模式「阈值掩盖」；AC-010「应用退出时后台扫描进程被取消，不残留子进程」；`spec.md:55` 可测试性声明。
- 位置：`tests/unit/CommandConcurrencyTests.swift:57-86`（用例）、`:66-71`（4 个任务用 `try?` 吞掉退出结果）、`:237-243`（`waitUntilNotBusy` 轮询上限）；对照 `src/zmole/App/AppDependencies.swift:270-288`（实际 shutdown 处理器未被本用例驱动）。
- 问题：用例以 `sleep 5`（`["5"]`，timeout 30s）起 4 条真实进程，取消后仅断言 bridge 最终 `!isBusy` 且任务结束。`waitUntilNotBusy` 上限为 500×10ms（≥5.0s）：若 `cancel()` 变为 no-op 或被移出取消循环，`sleep 5` 自然退出同样使 bridge 变 idle、任务返回 success，用例全绿。实测本机 500 次 `Task.sleep(10ms)` 耗 6.874s（> sleep 5 的自然寿命），该窗口无法区分「取消生效」与「自然结束」；`try?` 又丢弃退出原因（当前实现实际以 `MoleBridgeError.cancelled` 结束，测试日志 elapsed_ms=13 可证），因此「进程被取消」语义在单元层仍无判别力验证——属 f002 修复的换形式弱化。删掉 `AppDependencies.installShutdownHandler` 对 `lanes.allProcessLanes` 的使用或把 scan lane 从循环中剔除时，本用例也不会失败。
- 建议：让 4 个任务返回捕获的错误并断言均为 `MoleBridgeError.cancelled`（最小改法）；或断言 cancel 后 idle 延迟远小于进程寿命（如 `sleep 30` + 1s 内 not-busy）；亦可断言每条 lane 的 `cancel` 计数 ≥1。

### 改测方向复核

- 无。本轮相对 Round 1 的测试改动均为新增（f001/f003 的补充用例、f002 的成员/在途用例），未删除或反转既有断言，未把预期改成当前实现输出。

### AC 复验方式（本轮）

- AC-001：re_verified — `testAllItemsStartInParallelAndUseReadOnlyCommands` 重跑绿（探针 max ≥ 2、runningItems == 4、5 条只读 argv）；空缓存全启 + fresh 零调用 + stale 单启三态齐备。
- AC-002：re_verified — 新用例独立验证取消、结果清除（内存 + 磁盘缓存）与「终止前不返回、终止后才返回」；defer 用例覆盖写入租约互斥。
- AC-003：re_verified — 临时目录缓存往返全等 + 启动零进程且 `service.result(for:)` 已可读。
- AC-004：re_verified — fresh 不扫/stale 重扫 + periodic 时钟推进用例（f003 已消除）。
- AC-005：re_verified — 运行中刷新进程数保持 1，完成后再次请求为 2。
- AC-006：re_verified — invalidation 清空并重扫 5 项；确认框打开时 adopt 不替换现有 preview。
- AC-007：re_verified — 失败保留旧候选、进入 failedItems、2h 退避后重试，其他项不受影响。
- AC-008：re_verified — 5 条正向 argv 精确断言 + 4 形态负向黑名单（未收紧为全量白名单，见提示）。
- AC-009：re_verified — 无 FDA 时 installer 0 调用，授权后 ≥1。
- AC-010：re_verified（有缺口）— 成员集合断言有效且重跑绿；在途终止语义的判别力缺口见 f004。
- AC-011：re_verified — 非 JSON 与 `schemaVersion: 0` 均按无缓存处理。
- coverage = 11/11

### 本轮结论

- 本轮新发现：1 条（important 1 / minor 0）。
- 未进表的提示：AC-008 负向检查仍为 4 个精确形态 + 5 条正向包含而非全量白名单；`CleanViewModel.previewClean/confirmAndRun`、`InstallersViewModel.scan`、`UninstallViewModel.loadList`、`MaintenanceViewModel.previewMaintenance` 对 `userDidRescan*` 的接线调用无测试（服务侧语义已测）；`AppDelegate.shutdownHandler` 的装配（`AppDependencies.installShutdownHandler`）无测试直接调用；`userDidRescan` 非等待变体与等待变体重复的移除 + 落盘代码仅后者有测试。全量 `xcodebuild test`（296 个用例）与聚焦重跑（25 个用例）均零失败；未发现其余恒真/删除断言/跳过/mock 误用模式。
- 总体判断：f001、f003 已真正修复，f002 成员部分已补但新增的在途取消验证存在容差掩盖（f004，important），本轮不通过。
- 系统性 follow-up：无。

verdict: FAIL

## Round 3 (2026-10-17T18:57:24+08:00)

reviewed_scope: 826705ec0043beef

### 前轮 finding 复核

- t043_test_f004（important，AC-010 在途取消被轮询容差掩盖）：已消除，判别力已补足。
  - 用例重写为 `sleep 60`（`tests/unit/CommandConcurrencyTests.swift:68`，timeout 120），退出错误不再被 `try?` 吞掉：`canceledError` 捕获并返回错误（:66-73），4 个任务全部断言 `error as? MoleBridgeError == .cancelled`（:91-98）。反事实推演：若 `cancel()` 变 no-op 或 scan lane 从取消集合剔除，`sleep 60` 在 `waitUntilNotBusy` 的 500×10ms（约 5-7s 上限，:250-256）窗口内不可能自然结束 → 先 `XCTFail("bridge never became idle")`，且任务自然退出返回 success（nil）→ 错误断言同样失败；若取消生效但错误形态变化（SIGTERM 走 commandFailed）也被错误断言捕获。若 lane 从 `allProcessLanes`（`src/zmole/App/MoleCommandLanes.swift:54-61`）摘除，成员用例 `testShutdownCoversBackgroundScanLanes`（:38-53）亦失败。
  - 本轮独立重跑：`testShutdownCancelsInFlightBackgroundScanProcesses` passed（0.123s）；桥内日志 `mole 60 failed=cancelled elapsed_ms=12/14/15/15`——进程在取消后约 13ms 终止，远小于 60s 自然寿命，容差掩盖已不存在。
  - 残余观察（不进表）：生产装配 `AppDependencies.installShutdownHandler`（`src/zmole/App/AppDependencies.swift:270-288`）对 `allProcessLanes` 的使用仍未被测试直接驱动（若仅在该函数体内过滤 scan lane，现有测试不可捕获）；Round 2 已列为提示，延续提示级。
- 其余历史 finding：f001/f003 Round 2 已消除，其用例本轮未改动、重跑仍绿；f002 成员部分有效，在途部分由 f004 修复承接。
- 契约区 drift 核对：AC-001 措辞与 AC-010 可测试性声明变更均与 `task.md` front matter 用户批准 note、当前测试实现一致，维持 Round 1 的非 blocking 判定。

### 改测方向复核

- 无「迁就实现」改测。本轮两处改动均为加强：AC-008 断言从「4 形态黑名单 + 5 条正向包含」改为全量白名单集合相等（`tests/unit/BackgroundScanTests.swift:24-34`，`XCTAssertEqual(Set(calls), allowed)` 使任何额外调用形态必然失败）；AC-010 用例把进程寿命从 5s 提到 60s、把被 `try?` 丢弃的退出原因改为断言 `.cancelled`，方向是提高判别力而非放宽预期。

### AC 复验方式（本轮）

- AC-001：re_verified — 全量重跑 296 用例零失败、聚焦重跑 25 用例零失败；`testAllItemsStartInParallelAndUseReadOnlyCommands` 断言 max≥2、runningItems==4、5 条 argv 集合相等。
- AC-002：re_verified — f001 用例重跑绿（预置旧结果、rescan 后内存/磁盘结果清除、`finishCancellation` 前 wait 不返回）。
- AC-003：re_verified — 缓存往返全等 + 启动零调用 + `result(for:)` 可读（重跑绿）。
- AC-004：re_verified — stale 重扫/fresh 不扫 + periodic 时钟推进用例重跑绿。
- AC-005：re_verified — 运行中刷新进程数保持 1、完成后为 2（重跑绿）。
- AC-006：re_verified — invalidation 后清空重扫 5 项、确认框打开期间不替换（重跑绿）。
- AC-007：re_verified — 失败保留旧候选、进入 failedItems、2h 退避重试、其他项不受影响（重跑绿）。
- AC-008：re_verified — 本轮复验收紧后的全量白名单集合相等断言（`tests/unit/BackgroundScanTests.swift:31`），重跑绿。
- AC-009：re_verified — 无 FDA 0 调用、授权后 ≥1（重跑绿）。
- AC-010：re_verified — 成员用例 + 重写后的在途取消用例重跑绿；日志证取消后约 13ms 进程终止且任务以 `.cancelled` 收尾。
- AC-011：re_verified — 非 JSON 与旧 schema 均按无缓存处理（重跑绿）。
- coverage = 11/11

### 本轮结论

- 本轮新发现：0 条。
- 未进表的提示：AC-010 生产装配 `AppDependencies.installShutdownHandler` 未被测试直接驱动（若在该函数体内过滤 scan lane 现无测试可捕获，沿用 Round 2 提示）；`userDidRescan` 非等待变体与等待变体重复的移除+落盘代码仅后者有测试；`CleanViewModel.previewClean/confirmAndRun`、`InstallersViewModel.scan`、`UninstallViewModel.loadList`、`MaintenanceViewModel.previewMaintenance` 对 `userDidRescan*` 的接线无测试（服务侧语义已测）。
- 总体判断：f004 真正修复且判别力充分（60s 寿命 vs 约 5s 轮询界、错误断言、成员断言三重区分），AC-008 已收紧为全量白名单；无未解决的 critical/important，本轮通过。
- 系统性 follow-up：无。

verdict: PASS

## Round 4 (2026-10-17T19:08:28+08:00)

reviewed_scope: 17abd136a2cec471

### 前轮 finding 复核

- t043_test_f001（important，AC-002 恒真断言/无法区分等待终止）：仍消除。用例 `testUserCleanScanCancelsAndWaitsForBackgroundClean`（`tests/unit/BackgroundScanTests.swift:40-69`）未改动，本轮生产改动（`task.cancel()` 提前、`cancelAndWait` 去掉收尾清 `tasks`、`request` 加 `deferredClean` 检查）不触碰其判别链条：`results.removeValue`（`BackgroundScanService.swift:146-148`）、`await task.value`（:187）、spy `finishCancellation`（`tests/unit/BackgroundScanTests.swift:657-660`）均在；本轮重跑通过（0.130s）。反事实仍成立（删 :146-148 或删 :187 用例必失败）。
- t043_test_f002（minor，AC-010 仅成员断言）：维持 Round 2/3 结论。`testShutdownCoversBackgroundScanLanes`（`tests/unit/CommandConcurrencyTests.swift:38-53`）成员断言有效；「取消计数」部分已由 spec 可测试性声明同步（drift 已确认）与 f004 的在途取消用例承接。
- t043_test_f003（minor，AC-004 periodic 路径零覆盖）：仍消除。`testPeriodicRefreshRescansStaleResults`（`tests/unit/BackgroundScanTests.swift:147-166`）未改动，重跑通过（0.268s）；删除 `startPeriodicRefresh` 或 init 调用后该用例必超时失败。
- t043_test_f004（important，AC-010 轮询容差掩盖）：仍消除。`testShutdownCancelsInFlightBackgroundScanProcesses`（`tests/unit/CommandConcurrencyTests.swift:57-99`）未改动：`sleep 60`（:68）远超 `waitUntilNotBusy` 的 500×10ms 窗口（:250-256），4 个任务断言 `MoleBridgeError.cancelled`（:91-98）；本轮重跑通过（0.027s）。

### t043_test_f005 - 本轮 clean 并发修复（request 的 deferred 压制、cancelAndWait 收尾）无测试覆盖，回归无防线

- 严重度：minor
- 锚点：AC-002「clean 扫描与 clean 用户刷新/执行互斥……观测不到两个进程同时写 `clean-list.txt`」的用户接管窗口分支；对应 code reviewer `t043_code_f002`（deferred 压制）与 `t043_code_f003`（cancelAndWait 收尾）的修复未配套测试。
- 位置：`src/zmole/Features/Operations/BackgroundScanService.swift:174`（`if deferredClean { return }`）、`:128`、`:144`（`deferredClean = true`）、`:181-190`（`cancelAndWait` 收尾不再清 `tasks`）；唯一触发 deferred 的用例 `tests/unit/BackgroundScanTests.swift:71-92`。
- 问题：反事实推演——删除 `:174` 检查或 `:128`/`:144` 任一 flag 设置，本轮 296 条全量用例（含 25 条聚焦用例）全绿：唯一覆盖 deferred 的 `testCleanRequestDefersWhileWriteLeaseIsHeld` 的 deferred 由 `request` 的 `isCleanBusy` 分支（`:167-169`）设置，解除走 `noteActivityChanged()`（`:205-209`）先清 flag 再 request 的路径，永不经过 `:174`；该用例中 `cancelAndWait` 也因 clean 已完成（`tasks[.clean] == nil`）而早退，无法判别 `:181-190` 的收尾语义。回归场景：若检查被移除，周期 tick / invalidation 的 `refreshIfDue` → `request(.clean)`（结果已被 `userDidRescan*` 移除，`shouldRefresh` 返回 true）可在用户接管后、`ActivityCoalescer` 200ms 后才 `noteActivityChanged` 的窗口内启动第二个 `clean --dry-run`，与用户预览/执行竞争 `clean-list.txt`（code_f002 竞态复活）；`cancelAndWait` 重新加回 `tasks[item] = nil` 亦无测试可捕获（code_f003 场景需要精确调度构造，现有测试无此窗口控制）。
- 建议：新增一条用例覆盖 `:174`：`userDidRescanAndWaitForTermination(.clean)` 返回后（无 preview、无 lease），直接调用 `service.request(.clean)`（或 `refreshIfDue()`），断言 clean 进程调用数不增；随后 `noteActivityChanged()` 断言恰好启动一次。`cancelAndWait` 收尾可另行构造（阻塞 clean spy + `finishCancellation` 与 request 的调度窗口），难度较高，允许只覆盖前者并注明。

### 改测方向复核

- 无。本轮相对 Round 3 无测试文件改动：`tests/unit/BackgroundScanTests.swift` 行号与断言（白名单集合相等 :24-34、f001 用例 :40-69、periodic 用例 :147-166）及 `tests/unit/CommandConcurrencyTests.swift`（sleep 60 用例 :57-99）与 Rounds 2/3 报告引用逐条吻合，无删除/反转/弱化既有断言，无迁就实现的改测。生产侧改动（deferred 检查、cancelAndWait 收尾）未新增测试属本轮缺口，见 f005。

### AC 复验方式（本轮）

- AC-001：re_verified — 全量重跑 296 用例零失败、聚焦重跑 25 用例零失败；`testAllItemsStartInParallelAndUseReadOnlyCommands`（`tests/unit/BackgroundScanTests.swift:8-36`）断言 max≥2、runningItems==4、argv 白名单集合相等。
- AC-002：re_verified（含缺口）— `testUserCleanScanCancelsAndWaitsForBackgroundClean`（:40-69）与 `testCleanRequestDefersWhileWriteLeaseIsHeld`（:71-92）重跑绿；本轮修复的 deferred 压制窗口分支无测试，见 f005。
- AC-003：re_verified — `testCacheRoundTripAndFreshResultsSkipScanning`（:96-117）：临时目录缓存往返全等、fresh 零进程调用、`result(for:)` 可读。
- AC-004：re_verified — `testOnlyStaleResultsAreRefreshed`（:131-144）+ `testPeriodicRefreshRescansStaleResults`（:147-166，时钟推进 25h）重跑绿。
- AC-005：re_verified — `testRefreshWhileRunningReusesTheInFlightScan`（:170-184）重跑绿（运行中进程数 1，完成后 2）。
- AC-006：re_verified — `testInvalidationClearsResultsAndRescansEverything`（:187-205）+ `testCleanPageAdoptsBackgroundResultAndProtectsTheConfirmation`（:330-363）重跑绿。
- AC-007：re_verified — `testFailingItemKeepsPreviousResultAndRetriesLater`（:209-235）重跑绿（保留旧候选、failedItems、2h 退避后第 2 次调用）。
- AC-008：re_verified — 白名单集合相等断言（:24-34，`XCTAssertEqual(Set(calls), allowed)`）。
- AC-009：re_verified — `testMissingFullDiskAccessDefersInstallerUntilGranted`（:238-256）重跑绿。
- AC-010：re_verified — `testShutdownCoversBackgroundScanLanes`（`tests/unit/CommandConcurrencyTests.swift:38-53`）+ `testShutdownCancelsInFlightBackgroundScanProcesses`（:57-99，重跑 0.027s，断言 `.cancelled`）。
- AC-011：re_verified — `testCorruptOrOldSchemaCacheIsIgnored`（:119-127）重跑绿（非 JSON 与旧 schema 均按无缓存处理）。
- coverage = 11/11

### 本轮结论

- 契约区 drift 核对：AC-001 措辞与 AC-010 可测试性声明变更与 `task.md` front matter 用户批准 note、当前测试实现一致，维持 Round 1–3 的非 blocking 判定。
- 改测方向复核：无（本轮无测试改动）。
- 本轮新发现：1 条（minor 1 / important 0 / critical 0）。生产修复方向已由代码核实（`BackgroundScanService.swift:174`、`:181-190`），但测试未配套，回归无防线。
- 未进表的提示：沿用 Round 3 提示（`installShutdownHandler` 装配未被测试直接驱动；`userDidRescan*` 接线与 `CleanViewModel.previewClean/confirmExecution`、`InstallersViewModel.scan` 等调用点无测试）；补充 `userDidRescan` 对 `.installerList` 的 `deferredInstaller = false`（`BackgroundScanService.swift:129`）同样无测试；`tests/unit/BackgroundScanTests.swift` 807 行（超 600 提示阈值，沿用 code reviewer 提示级）。
- 总体判断：前轮 4 条 finding 均已消除且用例未退化；本轮生产改动方向正确但未配套测试（f005 minor），无未解决的 critical/important，本轮通过。
- 系统性 follow-up：无。

verdict: PASS
