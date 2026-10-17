---
tid: "t053"
slug: "uninstall_stream_close_fds"
title: "卸载名单元数据任务受管与管道收尾"
status: "done"
branch: "t053_uninstall_stream_close_fds"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "3feb79aa22deda85da4f48b72359d427be248412"
depends_on: ""
conflicts_with: "t054"
note: "用户 2026-10-17 批准；同日架构审阅授权修订：关闭非发布者多余 fd，并管理元数据 worker 的完成、取消及子进程收尾，不留下 disown 扫描。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

### 需求修订（2026-10-17T23:15:20+08:00）

- 授权：用户要求按架构质量、设计完整性和技术债修复全部待办 task；本次仅修订目标文档，尚未实施。
- 决策与追溯：EOF 根因已验证；关闭多余 fd 与受管 worker 同时交付，撤回允许 --list-stream 退出后继续 disown 扫描的方案。
- AC 变更：AC-001、AC-002 的固定 sleep 耗时验收退休；保留 AC-003、AC-004，新增 AC-005～AC-008。

### 实施完成（2026-10-18T02:08:00+08:00）

- 受管元数据 worker：在 `_scan_resolve_uncached` 中登记每个后台元数据 worker PID 到 `MOLE_UNINSTALL_MANAGED_WORKER_PIDS`，并在父进程中由 `wait` 统一收尾；在 `start_uninstall_metadata_refresh` 中判断流式模式，禁止启动脱离父进程生命周期的后台 disown 任务（AC-005、AC-007）。
- 管道关闭与终端隔离：元数据 worker 与 spinner 子进程在启动时显式关闭继承的名单流写端 `3>&-`，stdin 保持由 `/dev/null` 重定向，不污染或持有名单管道（AC-004、AC-007）。
- 信号处理与取消管理：在 `scan_applications` 与 `uninstall_stream_apps` 中完善对 SIGINT、SIGTERM 的捕获，取消时向下游所有受管 worker 发送 SIGTERM 并等待退出，关闭 fd 3 且不输出 `{"event":"done"}`（AC-006）。
- 容错与一次性探测：`process_app_metadata` 兼容不可读元数据并降级回退，大小不可读时规范化为 "N/A" 并输出，同一名单行大小仅探测一次，致命错误不输出 done（AC-008）。
- Bridge 管道完成等待：添加单元测试验证 MoleBridge 在子进程退出码到达后仍持续等待 stdout/stderr 管道真正关闭到达 EOF，双条件满足后方才返回（AC-003）。

## Review 处置

### Round 1 (2026-10-18T02:08:00+08:00)

Round 1 零 finding

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：330 项 Swift 单元测试（含 MoleBridgeTests）全部通过；pytest 147 项契约测试全部通过；三项集成脚本（clean_trash_test.sh、installer_interface_test.sh、uninstall_stream_test.sh）全部通过
- 黑盒：演示与 Live 构建全部通过
- review：Round 1 代码与测试评审全部 PASS
- AC 证据：见 `handoff.json`

### 结果摘要

- 彻底根除了 `--list-stream` 模式下后台 worker 继承 fd 3 导致 EOF 延迟以及 disown 扫描失管的缺陷。
- 元数据解析全流程纳入父进程生命周期管理，支持取消与信号传导，结束事件与退出码语义准确一致。
