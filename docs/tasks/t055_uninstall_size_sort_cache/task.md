---
tid: "t055"
slug: "uninstall_size_sort_cache"
title: "卸载名单按归一化大小排序并缓存派生结果"
status: "backlog"
branch: ""
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: ""
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

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round N (YYYY-MM-DDThh:mm:ss+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t000_code_f001|critical/important/minor|已修/遗留/撤回|一句话|文件:行 / pNNN / tid|

无 finding 时写“Round N 零 finding”。

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足 / 未满足
- 测试：待执行时填写
- 黑盒：待执行时填写
- review：待执行时填写
- AC 证据：见 `handoff.json`

### 结果摘要

- 待执行时填写；遗留只写引用，不复制正文
