# Task spec

## 背景

clean 会永久删除。必须预览后确认。非 TTY 下 mole 会自动跑用户级清理，故 **未确认不得 spawn 无 `--dry-run` 的 clean**。

## 契约区

### 范围

- `clean --dry-run` → 展示 `clean-list.txt`（路径可注入/可读）并标明「执行会重扫」
- 确认后 spawn `clean`（无 dry-run）；取消则不 spawn 执行
- 复用 t003 确认组件
- 运行中可取消 Process（若已实现 Bridge 取消）

### 非范围

- `--external`、whitelist TUI、系统级 sudo 策略定制（沿用 mole osascript）

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：预览调用的 argv 含 `clean` 与 `--dry-run`
- [ ] AC-002：确认前，执行用 Bridge 方法调用次数为 0（无 dry-run 的 clean）
- [ ] AC-003：用户取消确认后，仍不出现无 `--dry-run` 的 clean
- [ ] AC-004：确认后 argv 为 `clean` 且不含 `--dry-run`
- [ ] AC-005：预览 UI 含「执行时会重新扫描、列表可能变化」的说明

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001–AC-004：假 Bridge spy 自动
- AC-005：UI 文案测试或 snapshot

## 上下文区

- 来源：ADR-004；mole 非 TTY 自动执行用户级 clean

### 有意不测

- 真机删除效果：不进自动测试

### 测试策略

- spy 参数与调用次数；真 `clean` 仅 `[deploy]` 可选，本 spec 不强制真删

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无。s001：`clean --dry-run` 写出 `$HOME/.config/mole/clean-list.txt`（分段标题 + `path  # size`）

### 风险与回退

- 风险：误 spawn 真实 clean
- 回退：执行路径单一入口，确认标志位未置起则 return

### 依赖与约束

- 依赖 t003；review_level=full

### Finalization 时更新的 blueprint

- 无
