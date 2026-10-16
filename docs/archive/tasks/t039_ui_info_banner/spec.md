# Task spec

## 背景

UI 对齐修复。2026-10-17 用户批准：说明条（info banner）统一为 demo 的蓝色样式。当前 app 用绿色 accent 或红色通用 notice，与 demo 的蓝色信息条观感不一致。

**参考 demo 在哪里：**

- 视觉权威：`docs/design/mole_desktop_demo_cn_final.html`。
    - 蓝色信息条 `.info-banner`：CSS 第 338 行；使用位置——`renderOptimize`（第 1115 行）、`renderPurge`（第 1153 行）、`renderHistory`（第 1178 行）。
    - 颜色 token：浅色 `--blue-soft:#eaf1ff`、文字 `#355b99`；深色 `--blue-soft:rgba(53,120,229,.16)`（第 399 行 `@media (prefers-color-scheme:dark)`，注意该媒体查询未覆盖 `.info-banner` 的文字色，实现时深色文字需取可辨的蓝色系）。
    - 对照方法：浏览器直接打开 HTML，或 headless Chrome `--blink-settings=preferredColorScheme=1|2` 强制浅深色截图；app 侧用 `Zmole --demo --demo-page optimize|purge|history --demo-state populated --demo-language zh-Hans --demo-appearance dark|light --demo-data-root <dir>`。
- 语义基线：`docs/design/ui_contract.md`（说明条内容文案与不伪造语义不变，仅样式对齐）。
- 设计 token 在 `src/zmole/App/MoleTheme.swift`（当前缺 blue/blueSoft），本 task 增加对应 token。

## 契约区

### 范围

- `MoleTheme` 增加蓝色系语义 token（blue / blueSoft / 可辨文字色），取值对齐 demo 浅深两套。
- 新增或改造信息条组件：蓝底、蓝色系文字、圆角与内边距对齐 demo `.info-banner`（可复用现有 `UtilityNotice` 增加 info 风格变体；错误与警告样式不变）。
- 应用位置：优化页说明条、项目清理页说明条、历史页说明条改为蓝色 info-banner 样式。
- 错误（红）与危险提示样式保持不变；`RecoverableBusyNotice` 语义不变。

### 非范围

- 不清洗其它 notice 文案。
- 不改错误/警告 notice 的颜色与语义。
- 页头（t035）与表格（t038）不属本 task。

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：优化页说明条为蓝底蓝色系文字样式，与 demo `.info-banner` 一致。
- [ ] AC-002：项目清理页说明条同款样式。
- [ ] AC-003：历史页说明条同款样式。
- [ ] AC-004：错误（红）与其它 notice 视觉不受影响。
- [ ] AC-005：浅色/深色下信息条文字可辨；三语文本不溢出、不裁切。

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001～AC-005：颜色与布局为视觉对照项，不可单测断言。替代验证：`--demo` 模式三页截图（浅深×三语）与 demo HTML 同视口渲染对照；token 取值可在构建产物中人工核对。

## 上下文区

- 来源：2026-10-17 用户批准「UI 级别 2 修复」（评估报告 e 项）。

### 有意不测

- 蓝色具体色值误差：在 demo token 值附近即视为一致，不设数值断言。

### 测试策略

- 组件级：如引入枚举式 notice 风格（info/warning/error），对风格→颜色映射补简单单测；其余截图对照。

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无。

### 风险与回退

- 风险：`UtilityNotice` 被多页复用，改造需保持错误与忙碌提示视觉不变；深色下文字对比度需实测。
- 回退：单 commit 还原。

### 依赖与约束

- 与 t035、t038 改同一批文件，需串行（conflicts_with 已标）。

### Finalization 时更新的 blueprint

- 无。
