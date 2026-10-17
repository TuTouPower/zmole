---
tid: "t052"
slug: "disk_measurement_queue"
title: "统一磁盘测量会话与统计上下文"
status: "done"
branch: "t052_disk_measurement_queue"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "95f591eb7760c8561a598f5607d4cb4b010223c5"
depends_on: ""
conflicts_with: "t046,t047"
note: "用户 2026-10-17 批准；同日架构审阅授权修订：修复队列停消费；区分目录自身合计和父贡献，按世代与语义共享，祖先结果完成全部消费者。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

### 需求修订（2026-10-17T23:15:20+08:00）

- 授权：用户要求按架构质量、设计完整性和技术债修复全部待办 task；本次仅修订目标文档，尚未实施。
- 决策与追溯：以会话级所有权解决队列停消费，并将硬链接上下文与共享身份纳入同一交付；不采用纯路径去重或仅抑制子任务的补丁。
- AC 变更：保留 AC-001～AC-004 的行为归属；新增 AC-005～AC-009。

### 实施完成（2026-10-18T01:46:00+08:00）

- 架构落地：实现 `DiskMeasurementSession`，作为磁盘测量的单一会话服务与状态所有者，管理任务排队、在途并发、世代与扫描状态；`AnalyzeViewModel` 仅负责页面浏览与交互展示，移除 ViewModel 内部旧 worker 与重复缓存。
- 队列与饥饿修复：重构队列消费循环，保证任务组取空后再入队持续消费，当待测与在途为空时确保持续更新 `isScanning=false`，消除 `pending=1, worker=false` 的假忙碌缺陷（AC-001、AC-002）。
- 统计上下文与硬链接分离：分离底层测量事实（device+inode 与分配块）与消费者去重贡献。`DiskEntry` 明确区分并独立记录 `selfDeduplicatedSize`（目录自身去重合计）与 `parentContribution`（对父目录的贡献）。兄弟目录间共享 inode 按规范化路径排序确定归属，避免并发完成顺序造成结果漂移（AC-005）。
- 祖先复用与世代刷新：进入在途祖先目录下的子树自动复用该祖先遍历，祖先遍历完成后回填已列出的全部等待行与 childCache，消除较新 listing generation 拦截结果的缺陷（AC-004、AC-006）；重新分析推进世代并丢弃旧世代结果，取消操作及时终止在途任务（AC-003、AC-007、AC-008）。
- 符号链接与跨设备：符号链接仅计自身，跨设备目录标记 `.otherDevice` 不计入父合计，不可读目录不伪装成 0（AC-009）。

## Review 处置

### Round 1 (2026-10-18T01:45:00+08:00)

Round 1 零 finding

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：329 项 Swift 单元测试（含 DiskScannerTests、DiskExplorerTests 及新增 DiskMeasurementSessionTests 覆盖全部 AC-001～AC-009）全部通过；pytest 147 项契约测试全部通过；三项集成脚本（clean_trash_test.sh、installer_interface_test.sh、uninstall_stream_test.sh）全部通过
- 黑盒：Demo 装配与 Live 编译验证全部 PASS，无编译警告
- review：Round 1 代码与测试评审全部 PASS
- AC 证据：见 `handoff.json`

### 结果摘要

- 成功重构磁盘测量层为统一会话服务 `DiskMeasurementSession`，彻底解决旧 worker 取空退出导致的队列饥饿与 `isScanning` 假忙碌问题。
- 精确解耦目录自身去重大小与对父范围贡献，兄弟目录硬链接贡献由规范化路径排序确定，保证逆转 worker 顺序后结果 100% 幂等。
- 统一祖先测量订阅与在途复用，消除由于 listing generation 递增导致的等待行永久卡在计算中的问题。
- 为后续 t056（有界内存预算）与 t058（概览复用统一测量）提供了稳定的会话目录摘要与直接子项访问接口。
