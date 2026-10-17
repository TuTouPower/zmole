# Task review t057（reviewer_focus: 代码）

- task：`t057_background_cache_off_main`
- spec：`docs/tasks/t057_background_cache_off_main/spec.md`
- diff_anchor：`a3da9732aba95f1c2283992406d5edbafa28ec39`
- target：`git -C '/Users/karson/kar/code/zmole_t057' diff a3da9732aba95f1c2283992406d5edbafa28ec39`
- round：1
- reviewed_at：2026-10-18T03:28:00+08:00

reviewed_scope: d05f94d65c78abce

## Findings

Round 1 零 finding

## 结论

- 前轮 finding 复核：Round 1，无前轮。
- 本轮新发现：0 条。
- 架构与并发安全核查：
    - 线程隔离：`BackgroundScanStorage` 为独立 actor，所有磁盘 I/O（`load`/`saveThrowing`）、JSON 编解码均在其内部串行执行，完全脱离 MainActor。
    - clean 读取隔离：`cleanPreviewStore.readAsync` 在后台 `Task.detached` 执行，`BackgroundScanService.cancelAndWait(.clean)` 延伸等待读取任务退出，释放 clean-list.txt 文件所有权。
    - Hydration 状态：`isHydrated` 显式公布；在 hydration 完成前不向页面发布空结果；加载完成后合并，迟到加载不覆盖内存中的较新扫描结果。
    - 合并窗口：普通成功结果采用 100 ms debounce，连续更新在 500 ms 强制推进落盘；失效版本（`applyImpact`）与用户取消作为优先写入立即写盘。
    - 错误与降级：写入失败保留上一完整文件与待写快照，暴露 `lastWriteError`，不伪造成功，支持 `retryPending()`；损坏/旧 schema 安全恢复为 `[:]`。
- 总体判断：代码严格遵循项目并发与架构规范，实现完整优雅，无冗余，无未解决 finding。

### AC 复验方式

- AC-001：`testAC001_ReadWriteAndJSONEncodingNotOnMainActor` 验证生产读写及编解码均不在主线程。
- AC-002：`testAC002_CleanReadAndParseNotOnMainActor` 验证 clean 文件读取解析在非主线程，且生成快照完整。
- AC-003：`testAC003_NormalResultsMergeWithin100msTrailingEdge` 验证小于 100ms 两次成功合并为一次原子写。
- AC-005：`testAC005_BlockedOldLoadDoesNotOverwriteNewerResultsOrFlashEmpty` 验证旧加载阻塞后放行不覆盖新结果。
- AC-006：`testAC006_StaleInvalidationPriorityWriteOvercomesOldSnapshot` 验证优先写入不被迟到旧写回退。
- AC-007：`testAC007_WatermarkAdvancesWithin500msAndFlushSavesTail` 验证连续多次更新在 500ms 内推进水位且 flush 保存尾批。
- AC-008：`testAC008_WriteFailureDoesNotCorruptFileAndKeepsPending` 验证原子写失败保留原文件与快照。
- AC-009：`testAC009_CorruptOrUnsupportedSchemaRecoversAsEmptyWithoutError` 验证损坏文件安全恢复。
- AC-010：`testAC010_CleanTakeoverWaitsForReadingOwnershipBeforeProceeding` 验证 clean 接管等待在飞读取任务退出。
- coverage = 9/9（AC-004 已退役）

verdict: PASS
