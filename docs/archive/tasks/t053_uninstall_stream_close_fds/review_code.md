# Task review t053（reviewer_focus: 代码）

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

- 本轮新发现：0 条
- 未进表的提示：无
- AC 复验方式：
  - AC-003：re_verified，查验 MoleBridge.finishIfReady 门禁要求 processTerminated 与 stdoutEOF/stderrEOF 同时满足，由 MoleBridgeTests.testBridgeWaitsForPipesToCloseEvenIfProcessHasExited 独立复验。
  - AC-004：re_verified，查验 process_app_metadata 与 spinner 均由 `< /dev/null` 重定向 stdin，由 uninstall_stream_test.sh 独立复验。
  - AC-005：re_verified，查验 _scan_discover_apps 在 worker 解析前向 fd 3 发布身份行，worker 由父进程登记并在完成后由 wait 收尾，由 uninstall_stream_test.sh (AC-005) 独立复验。
  - AC-006：re_verified，查验 uninstall_stream_apps 与 scan_applications 信号捕获 (SIGTERM/SIGINT) 杀灭受管 worker 并静默退出，不输出 done，由 uninstall_stream_test.sh (AC-006) 独立复验。
  - AC-007：re_verified，查验 worker 显式关闭写端 `3>&-`，start_uninstall_metadata_refresh 在流式模式下不启动后台 disown 任务，由 uninstall_stream_test.sh (AC-007) 独立复验。
  - AC-008：re_verified，查验 process_app_metadata 容错与一次性探测，不可读 App 规范化为 "N/A" 并输出，致命错误不输出 done，由 uninstall_stream_test.sh (AC-008) 独立复验。
  coverage = 6 / 6
- 总体判断：所有行为 AC 均精确实现，消除了后台 worker 脱离生命周期和管道写端未关的缺陷，无 critical / important finding。
- 系统性 follow-up：无

verdict: PASS
