# 项目交接记录（最新）

本文件只保留当前有效一节。过时段落由 `repo-hygiene` 迁入 `docs/archive/handoff.md`。

## 2026-10-17T10:30:00+08:00 adoption-review → owner

- 当前焦点：`docs/reviews/review_20261017_054534` 采纳项（A1–A85）在隔离 worktree 落地中；实施完成后需跑全量门禁并在用户确认后合并。
- branch：adoption_20261017（worktree `../zmole_adoption_20261017`；基点 main `288e3e5`，审阅归档 commit）
- head_commit：288e3e5（worktree 内的采纳项改动尚未提交）
- 已完成：t001–t039 全部归档；UI 基线（t035–t039）落地；审阅与决策归档（288e3e5）；MoleBridge 加固、i18n 错误 key、并发/取消/日志等采纳项在 worktree 实施
- 未完成：采纳项全量验证（xcodebuild test + 集成脚本）；`docs/specs_index.md` 需求级 spec 全量补写（A82）；运行截图入库（A83）；Release zip 终验
- 陷阱：不公证（Gatekeeper 步骤见 README）；退出清理已由 AppDelegate 取消活跃 runner（限时 2s）；demo 数据根仅接受临时目录内路径；不 spawn 系统 `mo`
- 下一步：worktree 内 `docs/reviews/review_20261017_054534/adoption_decision.md` 为唯一范围来源；验证通过后由用户决定合并与后续 task
