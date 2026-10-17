---
tid: "t055"
slug: "uninstall_size_sort_cache"
title: "卸载名单按归一化大小排序并缓存派生结果"
status: "done"
branch: "t055_uninstall_size_sort_cache"
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: "90e4427b9a5b264c5d6a6d7b624effc56003de66"
depends_on: ""
conflicts_with: "t047,t049"
note: "用户 2026-10-17 批准；同日架构审阅授权修订：保存归一化大小；内容版本、筛选、排序和 Locale 构成缓存键，图标独立更新。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

### 需求修订（2026-10-17T23:15:20+08:00）

- 授权：用户要求按架构质量、设计完整性和技术债修复全部待办 task；本次仅修订目标文档，尚未实施。
- 决策与追溯：保留已验证方案，补充大小单一权威、行身份缓存、Locale 键及稳定同键顺序，避免缓存图标快照或重复可写字段。
- AC 变更：保留 AC-001～AC-004，新增 AC-005、AC-006。

### 实施完成（2026-10-18T02:53:00+08:00）

- 归一化整数大小存储：在 `UninstallAppListing` 与 `UninstallApp` 初始化与解码时计算并保存归一化整数 `sizeBytes`，作为排序与求和的唯一输入，文本与整数严格联动且禁止独立修改，比较期间无需反复调用 `HumanSizeParser`（AC-001）。
- 排序与筛选缓存机制：在 `UninstallViewModel` 中引入 `contentVersion` 与以 `(contentVersion, search, source, sort, locale.identifier)` 为键的派生缓存；图标更新独立发布不增加内容版本，单行图标即时刷新且不引发列表全量重排（AC-002、AC-003、AC-005）。
- 选择合计与未知提示：引入 `UninstallSelectionSummary` 统一使用归一化大小统计已知字节数并显式标记是否存在未知项（AC-004）。
- 稳定排序与 Locale 适应：`UninstallListOrder` 规范化实现名称升序、大小降序（同大小名称降序，未知项沉底）、来源升序（空来源置前），并使用 locale 敏感字符串比较；全同键项保持稳定身份排序（AC-001、AC-005、AC-006）。

## Review 处置

### Round 1 (2026-10-18T02:53:00+08:00)

Round 1 零 finding

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：336 项 Swift 单元测试（含 UninstallSizeSortCacheTests）全部通过；pytest 147 项契约测试全部通过；四项集成测试脚本全部通过
- 黑盒：演示与 Live 构建全部通过
- review：Round 1 通用评审 PASS
- AC 证据：见 `handoff.json`

### 结果摘要

- 实现了卸载名单归一化大小计算、排序缓存与图标分离架构。
- 彻底消除了每次 SwiftUI 视图重绘中对几百项数据重复解析大小字符串与重新排序的性能瓶颈。
- 保证了在不同语言 Locale 环境下排序结果与稳定行身份一致。
