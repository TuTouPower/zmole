# Task review t053（reviewer_focus: 测试）

- task：`t053_uninstall_stream_close_fds`
- spec：`docs/tasks/t053_uninstall_stream_close_fds/spec.md`
- diff_anchor：`3feb79aa22deda85da4f48b72359d427be248412`
- target：`git -C '/Users/karson/kar/code/zmole_t053' diff 3feb79aa22deda85da4f48b72359d427be248412`
- round: 1
- reviewed_at: 2026-10-18T02:08:00+08:00

reviewed_scope: bb6ecca12e96cffd

## Findings

无

## 结论

- 改测方向复核：无；既有测试全部保持原断言预期，旧测试无任何弱化或迁就修改；新增针对 AC-003～AC-008 的端到端集成测试与单元测试。
- 本轮新发现：0 条
- 未进表的提示：无
- AC 复验方式：
  - AC-003：re_verified，MoleBridgeTests.testBridgeWaitsForPipesToCloseEvenIfProcessHasExited 断言子进程退出后 Bridge 保持忙碌等待管道 EOF，并在关闭后捕获退出码。
  - AC-004：re_verified，uninstall_stream_test.sh 断言元数据 worker 重定向自 /dev/null。
  - AC-005：re_verified，uninstall_stream_test.sh 使用 MOLE_TEST_METADATA_BLOCK_FILE 阻断 worker 时断言身份行立即可见、done 未发出、父进程存活；放行后断言 done 到达且无存活 worker。
  - AC-006：re_verified，uninstall_stream_test.sh 在 worker 运行期间发送 SIGTERM，断言受管 worker 退出且不输出 done。
  - AC-007：re_verified，uninstall_stream_test.sh 双向对照断言关闭 fd 3 时 EOF 不延迟（19ms），保留 fd 3 对照组确实延迟等待（234ms）。
  - AC-008：re_verified，uninstall_stream_test.sh 断言不可读应用保留身份并规范化为 "N/A" 大小，致命路径不发出 done。
  coverage = 6 / 6
- 总体判断：测试真实触达生产脚本与桥接管道，涵盖正反对照、并发阻断与信号取消，无危险模式，测试可信度高。
- 系统性 follow-up：无

verdict: PASS
