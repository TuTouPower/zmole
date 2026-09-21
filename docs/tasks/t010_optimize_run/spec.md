# Task spec

## 背景

optimize 无 JSON，但 `--dry-run` 可跑。预览用 stdout 摘要；确认后再执行。

## 契约区

### 范围

- `optimize --dry-run` 展示输出（可滚动文本）
- 确认后 `optimize`；取消不 spawn 非 dry-run
- 预览失败时禁用执行

### 非范围

- optimize whitelist TUI；改维护任务集合

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：预览 argv 含 `optimize` 与 `--dry-run`
- [ ] AC-002：预览非零退出时执行按钮不可用
- [ ] AC-003：未确认不 spawn 无 `--dry-run` 的 optimize
- [ ] AC-004：确认后 argv 为 `optimize` 且无 `--dry-run`

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- 全部 AC 可自动测试

## 上下文区

- 来源：ADR-004；`s001` 验证 dry-run 退出码

### 有意不测

- 各维护任务副作用：不测

### 测试策略

- spy argv 与失败禁用

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无 TTY 时 optimize dry-run 是否非零：`UNVERIFIED-SPIKE`，`s001`

### 风险与回退

- 风险：摘要不可读（ANSI）
- 回退：剥 ANSI 再展示

### 依赖与约束

- 依赖 t008

### Finalization 时更新的 blueprint

- 无
