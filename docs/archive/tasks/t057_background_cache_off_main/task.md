---
tid: "t057"
slug: "background_cache_off_main"
title: "后台缓存串行存储与版本持久化"
status: "done"
branch: "t057_background_cache_off_main"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "a3da9732aba95f1c2283992406d5edbafa28ec39"
depends_on: "t049"
conflicts_with: "t046,t048,t051,t056,t058"
note: "用户 2026-10-17 批准；同日架构审阅授权修订：唯一串行存储移出 MainActor；普通结果合并、失效版本优先，覆盖加载竞态、失败降级与退出尾批。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

### 需求修订（2026-10-17T23:15:20+08:00）

- 授权：用户要求按架构质量、设计完整性和技术债修复全部待办 task；本次仅修订目标文档，尚未实施。
- 决策与追溯：从线程迁移升级为单一串行存储与版本一致性；区分普通结果合并和失效版本优先持久化，缓存失败不阻断业务操作，退休 schema=1 限制。
- AC 变更：保留 AC-001～AC-003；AC-004 的 schema=1 契约退休，新增 AC-005～AC-010。

### 实施进展（2026-10-18T03:26:00+08:00）

- 串行存储所有者：新增 `BackgroundScanStorage` actor，持有已接受修订号、待写快照与落盘水位，文件 I/O、原子写入与 JSON 编解码离开 MainActor。
- 显式 Hydration 状态：`BackgroundScanService` 引入 `isHydrated` 显式状态，加载前不向页面发布空缓存；异步加载完成后按版本与时间合并，迟到加载不可覆盖内存新结果。
- 合并窗口与优先级写入：普通成功结果以 100 ms 尾沿合并，连续更新每 500 ms 强制推进一次水位；失效版本与手动重置作为高优先级立即串行落盘；支持 `flush()` / `close()` 优雅退出及尾批落盘。
- 错误隔离与保留快照：原子写失败保留上次完整文件与待写快照，暴露 `lastWriteError`，不伪造成功，支持 `retryPending()`，业务操作不因缓存失败受阻。
- Clean 共享所有权：后台 clean 读取与解析移出 MainActor，用户 clean 接管时除取消进程外等待在飞读取任务退出，避免竞争写者。
- 页面接入：`UninstallViewModel` 与 `InstallersViewModel` 在 `loadListIfNeeded()` 显式等待 hydration，防止页面打开瞬间读取到未 hydration 状态。
- 验证：新增 `tests/unit/BackgroundCacheOffMainTests.swift` 覆盖全部 AC，全量 350 个单元测试与 4 个集成测试全部通过。

## Review 处置

### Round 1 (2026-10-18T03:27:00+08:00)

Round 1 零 finding

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：350 个单元测试通过，4 个集成测试通过
- 黑盒：非 UI 视觉修改，全部 AC 均已由自动化单测覆盖
- review：full 级审查完成，零 finding
- AC 证据：见 `handoff.json`

### 结果摘要

- 实现了后台缓存串行存储所有者 `BackgroundScanStorage`，将持久化与 clean-list.txt 解析移出 MainActor。
- 实现了显式 hydration 管理、100ms 尾沿合并/500ms 强制推进、失效版本优先串行写入以及 clean 接管所有权保证。
- 新增 `BackgroundCacheOffMainTests.swift` 验证 AC-001～AC-010。
