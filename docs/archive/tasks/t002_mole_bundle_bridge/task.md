---
tid: "t002"
slug: "mole_bundle_bridge"
title: "捆绑 mole 与 MoleBridge"
status: "done"
branch: "t002_mole_bundle_bridge"
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: "c7d06d7d6e9726c0ac831a9fce5a463e55b7545f"
depends_on: "t001"
conflicts_with: ""
note: ""
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

- 从上游 tag `V1.55.0`（`69ab325d4f05af0ea21aeeeae544046c9f04a76b`）复制 Bash 运行树；下载并校验同 tag 的 arm64/amd64 analyze/status helper，合成为 Universal binary。
- `MoleBridge` 以 bundle 内绝对路径定位入口，使用 actor + `Process` runner 实现 stdout/stderr、stdin、非零退出、busy、timeout 和进程组取消。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-09-21 14:12 UTC+8)

Round 1 零 finding。

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`xcodegen generate`；`xcodebuild` Debug build 通过；`xcodebuild test` 通过（7 tests）；`pytest .repo_template/tests -q` 通过（480 passed）；bundle 入口 `--version` 通过；主程序与两个 Go helper `lipo -archs` 均含 `x86_64 arm64`
- 黑盒：`blackbox_verify` 未定义；通过捆绑入口命令验证版本输出，功能页不在本 task 范围
- review：`review_general.md`，Round 1 PASS，零 finding
- AC 证据：见 `handoff.json`

### 结果摘要

- 交付固定版本 mole 运行树、Universal helper 和可取消的 MoleBridge；遗留只写引用，不复制正文
