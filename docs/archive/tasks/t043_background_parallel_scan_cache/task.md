---
tid: "t043"
slug: "background_parallel_scan_cache"
title: "后台并行扫描与 24 小时缓存"
status: "done"
branch: "t043_background_parallel_scan_cache"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "a7dc728648e71029b450d300ed12b734bbff828d"
depends_on: ""
conflicts_with: ""
note: "用户 2026-10-17 批准：预览改后台扫描；独立项并行；结果落盘；每 24 小时刷新；仅应用运行期间。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

- 新增 `BackgroundScanService`（`src/zmole/Features/Operations/BackgroundScanService.swift`）：五项只读扫描各起独立任务并行执行；启动加载缓存、缺失或超过 24 小时的项重扫；周期 tick 默认 60s 检查时效；失败保留上次结果并最多每小时重试；写入租约吊销后经监听重扫；FDA 未授权时安装包项延后。
- 新增 `BackgroundScanCache`（同目录）：schemaVersion 1 的 JSON 落盘到 `~/Library/Application Support/zmole/background_scan_cache.json`；损坏或旧 schema 整文件忽略。领域类型补 `Codable`：`CleanPreviewSnapshot`/`CleanPreviewGeneration`/`CleanPreviewEntry`/`CleanPreviewSection`/`UninstallAppListing`，`InstallerCandidate` 由 Decodable 扩为 Codable。
- clean 互斥：用户预览与执行前调用 `userDidRescanAndWaitForTermination(.clean)` 取消并等待后台进程；`deferredClean` 压制取消到用户取租约间隙内的周期重扫；`isCleanBusy` 同时看用户活动与写入租约。
- `MoleCommandLanes` 增加 5 条后台扫描通道（`BackgroundScanLanes`），`allProcessLanes`/`allStreams` 纳入 shutdown 取消集合；`AppDependencies` 装配服务并新增 `backgroundScanEnabled`（测试关闭，避免单元测试启动真实扫描与污染 Application Support 缓存；该污染在实现期被测试发现并修复）。
- `PrewarmService`/`PrewarmItem`/`PrewarmPayload`/`PrewarmResult`/`PrewarmResultProviding` 与 `tests/unit/PrewarmTests.swift` 整体删除。理由：串行队列、单 worker、空闲门控、consume-once 语义与本 task 的并行+持久缓存契约整体冲突，就地改断言会变成按实现改测试；旧文件中仍成立的页面采纳与确认保护用例已按新语义等价保留在 `tests/unit/BackgroundScanTests.swift`（uninstall/installers 采纳、clean 确认保护、optimize/purge 采纳）。
- 测试 spy 均在进程/流边界；服务测试使用真实 `BackgroundScanService`/`BackgroundScanCache`/`CleanPreviewStore`/`UninstallListStream`/`InstallerInterface`/`OperationCoordinator`，缓存全部写临时目录。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-10-17T18:41:00+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t043_code_f001|minor|已修|cancelAndWait 先翻转任务取消位再等通道，消除取消窗口内回写陈旧结果|src/zmole/Features/Operations/BackgroundScanService.swift:179|
|t043_test_f001|important|已修|AC-002 用例预置既有结果、区分等待终止前后、断言内存与磁盘结果被清除|tests/unit/BackgroundScanTests.swift:38|
|t043_test_f002|minor|已修|补成员集合断言并在 Round 2 补在途取消用例（后由 f004 修正判别力）|tests/unit/CommandConcurrencyTests.swift:38|
|t043_test_f003|minor|已修|补 periodicTick + 可变时钟用例，推进 24h 后断言重扫|tests/unit/BackgroundScanTests.swift:145|

### Round 2 (2026-10-17T19:02:41+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t043_code_f002|minor|已修|request 的 clean 分支同时检查 deferredClean 与 isCleanBusy，deferred 仅由 noteActivityChanged 解除|src/zmole/Features/Operations/BackgroundScanService.swift:166|
|t043_code_f003|minor|已修|cancelAndWait 不再手动清 tasks，交由 run 的 defer 收尾，避免覆盖新注册任务|src/zmole/Features/Operations/BackgroundScanService.swift:176|
|t043_test_f004|important|已修|在途取消用例改 sleep 60、断言 MoleBridgeError.cancelled，取消 no-op 不再能通过|tests/unit/CommandConcurrencyTests.swift:57|

### Round 3 (2026-10-17T19:06:00+08:00)

Round 3 零 finding（代码轴 PASS，测试轴 PASS）。

### Round 4 (2026-10-17T19:08:00+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t043_test_f005|minor|遗留|deferred 压制与 cancelAndWait 收尾两条并发修复缺反事实测试；t044 重写 clean 刷新路径时补|p015|

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`xcodegen generate`；`xcodebuild test -scheme Zmole -destination 'platform=macOS'` 296 用例 0 失败；`xcodebuild build -configuration Release` 通过；`pytest .repo_template/tests -q -m contract` 147 通过；`tests/integration/clean_trash_test.sh`、`installer_interface_test.sh`、`uninstall_stream_test.sh` 全部通过；`git diff --check` 干净
- 黑盒：testing.md 的 demo smoke 已启动（zh-Hans、demo-data-root 隔离）；另用 Debug 构建启动真实应用：缓存命中三项（installer/uninstall/optimize）未重扫，缺失的 clean 与 purge 并行执行并分别落盘，clean 完成后缓存含五项且带 capturedAt；退出后无残留 mole 子进程
- review：full；code PASS（rounds 1-3）、test PASS（rounds 1-4）、`check_review_status.py overall=PASS review_scope=ok`、`reviewed_scope 17abd136a2cec471`
- AC 证据：见 `handoff.json`

### 结果摘要

- 后台五类只读扫描并行执行，结果持久化并在 24 小时内复用；用户 clean 与后台 clean 通过取消等待与 deferred 标记互斥；写入失效、失败保留/退避、FDA 延后、退出取消均有单元覆盖。
- 遗留：`p015`（deferred 压制与 cancelAndWait 收尾的反事实测试，minor）。
