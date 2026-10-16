# Task spec

## 背景

UI 对齐修复。2026-10-17 用户批准：历史页从「List 双分区堆叠」改为 demo 的对齐表格。

**参考 demo 在哪里：**

- 视觉权威：`docs/design/mole_desktop_demo_cn_final.html` 的 `renderHistory`（第 1178 行）；相关 CSS：`.history-row`/`.history-row.header`、`.history-size`、`.history-status`、`.info-banner`。
- 对照方法：浏览器直接打开 HTML，或 headless Chrome `--blink-settings=preferredColorScheme=1|2` 强制浅深色截图；app 侧用 `Zmole --demo --demo-page history --demo-state populated --demo-language zh-Hans --demo-appearance dark|light --demo-data-root <dir>`。
- 语义基线：`docs/design/ui_contract.md`「历史」行（数据来自 `history --json`；空记录显示空状态；导出把本次 JSON 原样写入用户选择的文件）。
- 设计 token 已对齐（`src/zmole/App/MoleTheme.swift`），无需改 token。

现状（`src/zmole/Features/History/HistoryView.swift`）：`List` 两个 Section（sessions / deletions）纵向堆叠；导出与刷新在窗口工具栏（页头统一由 t035 负责）。

数据结构（`src/zmole/Features/History/HistorySnapshot.swift`）：session 含 command/dateText/items/size；deletion 含 timestamp/mode/status/sizeKB/path。

## 契约区

### 范围

- 记录区改为对齐表格：列语义为 日期 / 操作 / 结果 / 状态（对齐 demo `.history-row.header`）。
    - session 行：日期=记录时间；操作=命令名；结果=条目数与容量（有则显示）；状态=已完成。
    - deletion 行：日期=时间戳；操作=被删路径（中部截断+完整路径可悬停/可选）；结果=容量（有则显示）；状态=现有 status 字段。
- 列宽对齐、表头样式与行分隔线参照 demo；窗口 1100×700 下不产生水平滚动。
- 空记录保留空状态展示。
- 导出 JSON 行为不变（入口位置以 t035 统一后的页头为准）。

### 非范围

- 页头与动作按钮位置（属 t035）。
- 导出文件格式与 `history --json` 取数逻辑。
- 说明条样式（属 t039）。

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：有记录时以对齐表格显示，表头为日期/操作/结果/状态四列，列对齐关系稳定。
- [ ] AC-002：session 与 deletion 两类记录都出现在表格中；deletion 行显示被删路径。
- [ ] AC-003：空记录显示空状态（不与表头空白混淆）。
- [ ] AC-004：导出 JSON 仍把本次 `history --json` 原文写入用户选择的文件，内容不变。
- [ ] AC-005：浅色/深色、简中/繁中/英文下表格可读；1100×700 无水平裁切。

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001、AC-005：视觉对照验证。替代验证：`--demo` 模式截图与 demo HTML 同视口渲染对照。
- AC-002～AC-004：可自动化——沿用现有 HistoryViewModel/HistorySnapshot 单测断言两类记录映射与导出原文一致。

## 上下文区

- 来源：2026-10-17 用户批准「UI 级别 2 修复」（评估报告 d 项）。

### 有意不测

- 列宽的具体像素值：设计近似。

### 测试策略

- 数据映射（session/deletion → 表格行）逻辑放 ViewModel 或可测 helper，补单测；视觉部分截图对照。

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无。

### 风险与回退

- 风险：现 `List` 的双 Section 在此改为单表后，两类记录的区分度下降；用状态或行语义保持可辨识。
- 回退：单 commit 还原。

### 依赖与约束

- 与 t035、t039 改同一文件，需串行（conflicts_with 已标）。

### Finalization 时更新的 blueprint

- `docs/design/ui_contract.md`：「历史」行如与实现描述有出入则同步。
