# 操作历史（history）

- 来源 task：t005、t024（history 部分）、t038
- 生效范围：历史页与导出
- 最后更新：2026-10-17

## 行为契约

- 数据来自 `mole history --json --limit 20`；默认 limit 20，请求 limit 下限 1、上限 200，UI 不发送 0。
- 有记录时以对齐表格展示（日期/操作/结果/状态列）；session 与 deletion 两类记录都出现，deletion 行显示被删路径。
- 空记录显示空状态（与表头空白可区分）；非零退出或非法 JSON 显示失败态（本地化错误键），不把空列表当成「没有历史」。
- 导出：把本次 `history --json` 原文写入用户选择的文件，内容不变；导出失败以独立可关闭 notice 展示，不顶替表格。
- 刷新按钮重跑列表命令；进行中禁用。

## 验证

- `tests/unit/ZmoleTests.swift`（loader argv、两类记录映射、空态与失败态）
- `tests/unit/SettingsHistoryTests.swift`（导出原文一致）
