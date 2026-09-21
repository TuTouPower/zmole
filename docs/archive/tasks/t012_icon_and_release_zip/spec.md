# Task spec

## 背景

公开发布需要独立图标（非 Mole 商标）。zip 与解压后验收改由 t013 在功能齐后做。本 task 只交图标与 Gatekeeper 说明，可与功能页并行。

## 契约区

### 范围

- 应用图标（macOS icns），视觉不模仿 Mole 地鼠官方标
- README 含：右键打开、系统设置「仍要打开」、`xattr -cr` 三条路径

### 非范围

- Developer ID、公证、dmg、Sparkle、打 Release zip（t013）

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：构建出的 `.app` 含 AppIcon，Dock/Finder 不显示空白占位（相对无图标工程）
- [ ] AC-002：README 同时出现「仍要打开」与 `xattr -cr`

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001：`[deploy]` 看 Finder/Info.plist 图标文件存在
- AC-002：读 README

## 上下文区

- 来源：ADR-003、ADR-005；p005 parked；审阅 P2 把打包验收从本 task 拆出

### 有意不测

- 各 macOS 版本 Gatekeeper 文案是否一字不差：不测

### 测试策略

- 图标资源存在性；README grep

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无

### 风险与回退

- 风险：图标太像 Mole 构成商标问题
- 回退：抽象字母 Z / 工具形，不用地鼠官方造型

### 依赖与约束

- 依赖 t001

### Finalization 时更新的 blueprint

- 无
