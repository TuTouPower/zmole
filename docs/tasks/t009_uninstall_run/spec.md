# Task spec

## 背景

`uninstall --list` 在非 TTY 下为 JSON。按 `uninstall_name` 预览/执行。禁止无名称选择器，禁止 `--permanent`。空 stdin 可能被当成确认，故未 GUI 确认不得 spawn 非 dry-run 卸载。

## 契约区

### 范围

- `--list` 展示已装 App；勾选
- 对选中名称 `--dry-run` 预览
- 确认后 `uninstall <uninstall_name…>`（可多个）
- 默认走 mole 废纸篓路径，不传 `--permanent`

### 非范围

- 无参数交互 TUI；永久删除开关

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：`--list` 夹具 JSON 展示 name 与 uninstall_name
- [ ] AC-002：预览 argv 含 `--dry-run` 与所选 uninstall_name
- [ ] AC-003：未确认时不 spawn 不含 `--dry-run` 的 uninstall
- [ ] AC-004：任何生产调用的 uninstall argv 不含 `--permanent`
- [ ] AC-005：未选择任何 App 时不能发起执行

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- 全部 AC 可自动测试

## 上下文区

- 来源：ADR-004；mole `uninstall --list` JSON 字段见上游源码

### 有意不测

- 真卸载本机 App：不测

### 测试策略

- 夹具 list JSON + spy argv

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- `--list` JSON 在捆绑 mole 上的实际输出：`UNVERIFIED-SPIKE`，`s001`

### 风险与回退

- 风险：名称匹配错误卸错 App
- 回退：只使用 JSON 的 `uninstall_name`，界面同时显示 name 与路径

### 依赖与约束

- 依赖 t008（共用确认组件行为）

### Finalization 时更新的 blueprint

- 无
