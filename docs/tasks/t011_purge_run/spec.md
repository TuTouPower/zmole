# Task spec

## 背景

s001 已核实：无 TTY 下 `purge --dry-run` 立即返回但名单为空（EOF=未勾选）。预览要用 `purge --dry-run --yes`（不删除、打印候选）；执行用 `purge --yes`。

## 契约区

### 范围

- 预览：`purge --dry-run --yes`，把 stdout 当名单/摘要
- 确认后执行：`purge --yes`（无 `--dry-run`）
- 未确认不 spawn 无 `--dry-run` 的 `--yes`
- 不存在既无 `--dry-run` 又无 `--yes` 的 purge

### 非范围

- `purge --paths` 配置 UI；无 `--yes` 的交互选择器

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：预览 argv 含 `purge`、`--dry-run` 与 `--yes`
- [ ] AC-002：执行 argv 含 `purge` 与 `--yes`，不含 `--dry-run`
- [ ] AC-003：未确认时，不含 `--dry-run` 的 `--yes` 调用次数为 0
- [ ] AC-004：代码路径中不存在「无 `--dry-run` 且无 `--yes`」的 purge

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- 全部 AC 可自动测试

## 上下文区

- 来源：ADR-004；mole `lib/clean/project.sh` 非 TTY 需 `--yes`

### 有意不测

- 真删 `node_modules`：不测

### 测试策略

- spy argv；预览夹具用 s001 `samples/purge_dry_run_yes.txt`

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无。s001：仅 `--dry-run` 无名单；`--dry-run --yes` 打印 `✓ [DRY RUN] path, size` 且不删文件。

### 风险与回退

- 风险：把预览的 `--yes` 和执行的 `--yes` 搞混，或漏 `--dry-run` 导致真删
- 回退：预览 argv 必须同时含 `--dry-run` 与 `--yes`；执行禁止 `--dry-run`

### 依赖与约束

- 依赖 t008；来源 s001 / d001

### Finalization 时更新的 blueprint

- 无
