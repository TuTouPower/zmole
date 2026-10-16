# Task review t026（reviewer_focus: 通用）

- task：`t026_overview_storage_estimate_cache`
- spec：`docs/tasks/t026_overview_storage_estimate_cache/spec.md`
- diff_anchor：`ec8bfbf37a782d1b3227cfd1aea7fca289fcd886`
- target：`git -C '/Users/karson/kar/code/zmole_t026' diff ec8bfbf37a782d1b3227cfd1aea7fca289fcd886`
- round：1
- reviewed_at：2026-10-16T22:10:06+08:00

## 复验命令

- `xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 191 passed / 0 failed（本机实测）。
- `pytest .repo_template/tests -q -m contract` → 147 passed / 367 deselected（本机实测）。

## Findings

### t026_gen_f001 - 失效信号落在估算扫描进行中时被丢弃，AC-004 边界不成立

- 严重度：minor
- 锚点：AC-004（收到 coordinator 失效信号后后台重算）
- 位置：`src/zmole/Features/Overview/OverviewViewModel.swift:93`–`:99`（订阅只置位布尔）、`:142`–`:167`（`computeEstimate` 末段无条件 `estimateInvalidated = false`）
- 问题：
    - 失效处理没有像同仓 `CleanViewModel`/`UninstallViewModel`/`MaintenanceOperation` 那样用 `invalidationGeneration` 做前后比较，只用一个布尔 `estimateInvalidated`，并在每次计算结束时无条件复位。
    - 时序：概览进入或 TTL 到期触发扫描，`isEstimating = true` 后 `await loadSums()`（4 次串行 `analyze`，可能数秒）。若此时另一页写入成功并 `invalidatePreviews()`，订阅置 `estimateInvalidated = true`；`.onChange` 发起 `refreshEstimateIfNeeded`，但被 `guard !isEstimating` 短路丢弃；原扫描结束后又把标志复位为 false。净效果：该次失效被吞掉，界面可能长时间停留在写入前的旧估算，直到下一次失效或 TTL。
    - 若失效到达时 `usedBytes` 仍为 nil，`computeEstimate` 的 `guard let usedBytes` 直接返回且不复位，标志停在 true；此时不再有触发点补算（`.task` 只跑一次）。
- 建议：进入扫描前记录 `generation`，结束后再比对；若期间 generation 变化或标志曾被置位，则保留 `needsRefresh` 并在扫描收尾再排一次计算。或改为「读取当前 generation → 扫描 → 若 generation 未变才复位」。

### t026_gen_f002 - 失败/全空求和也写入缓存并按“新鲜”处理，占位段最长 6h 不重试

- 严重度：minor
- 锚点：AC-005（失败段占位、成功段写缓存）+ 边界：桥不可用/全部目录失败时
- 位置：`src/zmole/Features/Overview/OverviewViewModel.swift:157`–`:166`（无条件 `save`）、`src/zmole/Features/Overview/StorageEstimateCache.swift:54`–`:56`（`isStale` 只看 capturedAt）、`OverviewViewModel.swift:122`–`:127`（新鲜即 `needsRefresh == false`）
- 问题：
    - `computeEstimate` 不论 `sums` 是否有任何成功段都调用 `storageCache?.save`。当 `lanes.estimate` 为 `UnavailableMoleProcess`（`MoleBridge()` 初始化失败）或 4 段全部瞬时失败时，会落盘一个全 nil 条目。
    - 该条目在 TTL 窗口内被视为有效且新鲜：下次进入概览 `primeEstimate` 从缓存渲染成全占位，`estimateNeedsRefresh` 因“新鲜”返回 false，不再扫描；即便桥恢复也要等 6h（页面停留期间）而非在下次启动即自愈。
    - 部分失败同理：某段瞬时超时被写入缓存后，该段作为占位被“新鲜”缓存固化，除非失效或 TTL 到期，不重试。
- 建议：至少在所有段皆 nil 时不写缓存（`成功段` 为空）；可考虑对含 nil 段的结果不视为可跳过扫描的“新鲜”缓存（例如不完整时允许一次补扫），避免占位被长期固化。

## 未进表的提示

- AC-002「先显示容量、五段占位、随后填充」中“先显示容量”无自动断言（view 层，历史各页均如此），可测部分已由 `testNoCacheFallsBackToScan` 覆盖。
- 非磁盘类写入（whitelist / purge paths 等）同样调用 `invalidatePreviews`，会导致一次全量 4-analyze 重扫，属规格“写入类成功后失效”的宽口径，成本可接受但可注意。
- 若首个含 `usedBytes` 的采样在 `.task` 的 12s 轮询窗口内未到，本次会话不补算（沿用 t016 f010 的已知模式），非本任务新增。

## 结论

- 本轮新发现：2 条（均 minor：f001、f002）
- 总体判断：AC-001/002/003/006 主路径成立且测试可信；缓存落盘位置、schemaVersion/capturedAt 字段、原子写、demo 旁路、独立只读通道（`lanes.estimate` = `bridges[8]`）、单飞守卫（`isEstimating`）均符合规格。f001 为失效信号在扫描窗口内的竞态，f002 为不完整缓存被“新鲜”固化，二者均为边界/健壮性缺陷，不阻断验收。
- 系统性 follow-up：失效语义建议统一走 `invalidationGeneration` 前后比较（与既有 ViewModel 一致），避免布尔复位在并发下丢失信号。

### AC 复验方式

- AC-001：`re_verified` — `primeEstimate`（`OverviewViewModel.swift:115`）从磁盘缓存渲染、不触发 analyze；`testPrimeRendersFromCacheWithoutRunningAnalyze` 断言段值且计数为 0。
- AC-002：`re_verified` — 无缓存时 `primeEstimate` 保持 `.placeholder`，`refreshEstimateIfNeeded` 回退扫描；`testNoCacheFallsBackToScan` 断言先占位后填充。
- AC-003：`re_verified` — `estimateNeedsRefresh` 对新鲜缓存返回 false；`testFreshCacheSkipsScan` 断言扫描计数为 0。
- AC-004：`re_verified`（含 f001 边界）— `testStaleCacheRefreshesInBackground` 断言过期重算并回写 `capturedAt`；`testCoordinatorInvalidationForcesRefresh` 断言失效置位、重算后清除。
- AC-005：`re_verified`（含 f002 边界）— `testFailedDirectoryLeavesPlaceholderAndSavesPartialCache` 断言失败段占位、其余渲染、成功段落盘。
- AC-006：`re_verified` — `StorageEstimateCache.load` 对 schema 不符/超 `maximumAge` 返回 nil；`testInvalidCacheIsIgnored` 断言两种情况。
- coverage = 6 / 6

verdict: PASS

### Round 2 (2026-10-16T22:16:02+08:00)

复核方式：重跑 `git -C '/Users/karson/kar/code/zmole_t026' diff ec8bfbf37a782d1b3227cfd1aea7fca289fcd886`，读当前源；`xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 193 passed / 0 failed；`pytest .repo_template/tests -q -m contract` → 147 passed / 367 deselected（均本机实测）。

自 Round 1 变更范围（仅 3 文件）：`OverviewViewModel.swift`（+`invalidationCount`、快照比较）、`StorageEstimate.swift`（`StorageSums.isComplete`）、`tests/unit/OverviewCacheTests.swift`（+2 测试）。其余 diff-touched 文件（`StorageEstimateCache.swift`、`OverviewView.swift`、`AppDependencies.swift`、`architecture.md`、`task.md`、`pbxproj`）与 Round 1 一致。

#### 上轮 finding 处置

- f001（失效信号落在扫描中时被丢弃）：**partially fixed**。`computeEstimate` 现于扫描前记录 `invalidationsAtStart = invalidationCount`，扫描收尾仅当计数未变才清 `estimateInvalidated`（`OverviewViewModel.swift:153`–`:171`）。订阅侧同时递增 `invalidationCount`（`:93`–`:99`）。扫描窗口内到达的失效不再被复位清除，`testInvalidationDuringScanKeepsEstimateStale` 用 `ScanGate` 阻塞首个目录探测、期间 invalidate、释放后断言标志仍为 true，测试可信。**残留**：只保住标志，未在扫描收尾补排一次计算——见新 finding f003。
- f002（不完整缓存被当作“新鲜”、占位段最长 6h 不重试）：**resolved**。新增 `StorageSums.isComplete`，`estimateNeedsRefresh` 在 `!cacheEntry.sums.isComplete` 时直接返回 true（`OverviewViewModel.swift:127`–`:133`），部分/全 nil 缓存不再抑制重扫；`testIncompleteCacheIsNotTreatedAsFresh` 断言部分缓存 `estimateNeedsRefresh == true`。全 nil（桥不可用）条目的 6h 固化问题随之消除。

#### 本轮新发现

### t026_gen_f003 - 扫描中失效只保住标志，未在收尾补排重算，页面停留时仍显示旧估算

- 严重度：minor
- 锚点：AC-004（收到 coordinator 失效信号后后台重算并更新缓存与界面）+ f001 残留
- 位置：`src/zmole/Features/Overview/OverviewViewModel.swift:153`–`:171`（收尾不清标志但也不重排）、`src/zmole/Features/Overview/OverviewView.swift:31`–`:34`（唯一触发是 `estimateInvalidated` 的 false→true 跳变）
- 问题：
    - 时序：扫描进行中（`isEstimating == true`）到达失效 → 订阅置 `estimateInvalidated = true`，`.onChange` 触发 `Task { refreshEstimateIfNeeded }`；该任务进入 `computeEstimate` 被 `guard !isEstimating` 立即短路丢弃。扫描收尾因计数变化不清标志，`estimateInvalidated` 停在 true，但值未再变化，`.onChange` 不会再次触发 → 无补排重算。
    - 结果：用户在概览页停留期间，写入后的估算不会被重算，界面继续显示写入前（或扫描早期目录）的旧值，须离开再返回（`.task` 重新进入时因标志为 true 才重算）或等到下一次失效。与 Round 1 f001 描述的“界面长时间停留旧估算”症状一致，仅信号不再被静默清除。
- 建议：在 `computeEstimate` 收尾检测到扫描期间发生失效时，主动再排一次计算（例如 `if invalidationCount != invalidationsAtStart { Task { await self.refreshEstimateIfNeeded(usedBytes: usedBytes) } }`），或在 `estimateNeedsRefresh`/视图侧对“标志为 true 且无在飞扫描”补齐触发；并补一条断言“扫描中失效后最终会发生一次重算”的测试。

#### AC 复验方式（Round 2）

- AC-001：`re_verified` — `primeEstimate`（`OverviewViewModel.swift:118`）从磁盘缓存渲染、不触发 analyze；`testPrimeRendersFromCacheWithoutRunningAnalyze` 断言段值且计数为 0。
- AC-002：`re_verified` — 无缓存时 `primeEstimate` 保持 `.placeholder`，`refreshEstimateIfNeeded` 回退扫描；`testNoCacheFallsBackToScan` 断言先占位后填充。
- AC-003：`re_verified` — `estimateNeedsRefresh` 对完整且新鲜缓存返回 false；`testFreshCacheSkipsScan` 断言扫描计数为 0。
- AC-004：`re_verified`（含 f003 残留）— `testStaleCacheRefreshesInBackground` 断言过期重算并回写 `capturedAt`；`testCoordinatorInvalidationForcesRefresh` 断言失效置位、重算后清除；`testInvalidationDuringScanKeepsEstimateStale` 断言扫描中失效不被清除（但未断言后续补算，见 f003）。
- AC-005：`re_verified` — `testFailedDirectoryLeavesPlaceholderAndSavesPartialCache` 断言失败段占位、其余渲染、成功段落盘；f002 修复后部分缓存不再被当“新鲜”从而抑制重试。
- AC-006：`re_verified` — `StorageEstimateCache.load` 对 schema 不符/超 `maximumAge` 返回 nil；`testInvalidCacheIsIgnored` 断言两种情况。
- coverage = 6 / 6

#### 结论（Round 2）

- 本轮新发现：1 条（minor ×1 = f003）
- 上轮处置：f002 resolved；f001 partially fixed（信号不再被清，但未补排重算，残留 f003）。
- 回归扫描：`isComplete` 只影响 `estimateNeedsRefresh` 的跳过判定，未破坏 AC-001（prime 仍无条件渲染）、AC-003（完整新鲜缓存仍跳过）；`invalidationCount` 仅在扫描收尾影响是否清标志，`testCoordinatorInvalidationForcesRefresh` 仍通过，无死循环（标志为 true 时 `.onChange` 不再跳变触发）。门禁 193/147 全绿，无回归。
- 总体判断：两处 Round 1 缺陷方向正确、AC 主路径与边界测试齐备；余下 f003 为扫描中失效后的补排缺失，用户可感知但窗口窄且下次进入自愈，不阻断验收。
- 系统性 follow-up：失效语义仍建议统一为 generation 前后比较并“收尾补算”，与既有 ViewModel 一致，避免布尔/计数在不同触发点下的丢算。

reviewed_scope: a1d3197121e9de5b

reviewed_scope: a1d3197121e9de5b

verdict: PASS
