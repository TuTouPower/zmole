---
tid: "t054"
slug: "brew_cask_index"
title: "卸载名单只建立一次 Homebrew cask 索引"
status: "done"
branch: "t054_brew_cask_index"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "39fa7f479616e613be59786fbb84860f97c5dae8"
depends_on: ""
conflicts_with: "t053"
note: "用户 2026-10-17 批准；同日架构审阅授权修订：父级扫描建立只读索引；唯一来源必须有真实路径或文件身份所有权，保留定向与执行期核验。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

### 需求修订（2026-10-17T23:15:20+08:00）

- 授权：用户要求按架构质量、设计完整性和技术债修复全部待办 task；本次仅修订目标文档，尚未实施。
- 决策与追溯：保留一次索引目标，明确父级构建与路径身份所有权，保留错误状态和执行期核验；快路径也使用同轮 installed 快照，避免把残留 Caskroom 当成已安装。t053 改为文件冲突。
- AC 变更：保留 AC-001～AC-003、AC-005；AC-004 的快路径完全不查安装状态契约退休，新增 AC-006～AC-009。

### 实施完成（2026-10-18T02:37:00+08:00）

- 扫描级 Cask 只读索引：在 `_init_brew_cask_scan_index` 中执行一次 `brew list --cask` 写入快照文件供当次扫描所有子任务复用；在 `_ensure_caskroom_index` 中对存在的 Caskroom 根进行至多一次遍历建立映射文件并用 `.ready` 标记防止重复遍历（AC-001）。
- 路径所有权快判与避免 info：`_detect_cask_from_scan_index` 优先匹配真实路径或设备+inode (`-ef`)，确认唯一已安装 token 后直接认领，完全不调用该应用的 `brew info`（AC-002）。
- 定向 probe 与重名候选项保护：同名应用产生多个候选或无直接文件身份时，仅对候选 token 执行定向 `brew info` 核验，未获所有权证明不认领任何 token，不随意选择首项（AC-003、AC-006）。
- 快路径零遍历与残留隔离：`_detect_cask_via_resolved_path` 支持快路径识别，若应用均命中快路径则 Caskroom 遍历严格为 0；残留但未在安装快照中的目录拒绝认领（AC-009）。
- 超时与隔离语义：probe 异常/超时 (124) 与确实未安装明确区分并传递（AC-007）；brew 不可用时快速跳过且不打 Homebrew 标（AC-005）；索引生命周期绑定至当次扫描，扫描结束后清理，后续扫描独立刷新（AC-008）。

## Review 处置

### Round 1 (2026-10-18T02:37:00+08:00)

Round 1 零 finding

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：330 项 Swift 单元测试全部通过；pytest 147 项契约测试全部通过；四项集成测试脚本（clean_trash_test.sh、installer_interface_test.sh、uninstall_stream_test.sh、brew_cask_index_test.sh）全部通过
- 黑盒：演示与 Live 构建全部通过
- review：Round 1 代码与测试评审全部 PASS
- AC 证据：见 `handoff.json`

### 结果摘要

- 实现了 Homebrew cask 扫描级只读索引与路径/文件身份所有权核验机制。
- 根除了以往每个待测应用反复调用 `brew list --cask`、多次遍历 Caskroom 以及多余 `brew info` 调用的严重性能缺陷。
- 保证了精确来源所有权检测，防止重名应用或残留未安装目录被错误认领。
