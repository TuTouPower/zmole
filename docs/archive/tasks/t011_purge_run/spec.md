# Task spec

## 背景

非 TTY 且**非 dry-run** 时，真实 purge 必须 `--yes`（`project.sh` 约 1682 行）。dry-run 不受该门闩限制。非 TTY 下 mole 自动勾选「非近期」项目，不读 stdin。s001 把「空名单」归因于 EOF/`--yes` 是错的：当时假 HOME 里没有合格候选，或项目仍算近期。

预览：`purge --dry-run`（不要为了预览强行加 `--yes`）。执行：`purge --yes`。

## 契约区

### 范围

- 预览：`purge --dry-run`，把**本次** stdout 当摘要
- 仅本次预览成功（exit 0）后可确认
- 确认后执行：`purge --yes`（无 `--dry-run`）
- 未确认不 spawn 无 `--dry-run` 的 `--yes`
- 不存在既无 `--dry-run` 又无 `--yes` 的 purge
- 复用 t008 预览过期、忙碌、取消、失败展示

### 非范围

- `purge --paths` 配置 UI；交互选择器；PTY

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：预览 argv 含 `purge` 与 `--dry-run`，**不含** `--yes`
- [ ] AC-002：执行 argv 含 `purge` 与 `--yes`，不含 `--dry-run`
- [ ] AC-003：未确认时，不含 `--dry-run` 的 `--yes` 调用次数为 0
- [ ] AC-004：代码路径中不存在「无 `--dry-run` 且无 `--yes`」的 purge
- [ ] AC-005：预览非零时确认不可用
- [ ] AC-006：确认取消或预览之后目标/条件变化（再次点预览）后，必须用新预览才能执行
- [ ] AC-007：执行中重复提交不创建第二进程；取消调用 Bridge cancel

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- 全部 AC 可自动测试

## 上下文区

- 来源：审阅纠正 s001；`project.sh` 非 TTY 自动选非近期；`--yes` 只放行真实执行

### 有意不测

- 真删 `node_modules`：不测

### 测试策略

- spy argv 与预览世代；预览夹具用 s001 `purge_dry_run.txt` / `purge_dry_run_yes.txt` 作文本形状参考，不以「必须 --yes 才能预览」为准

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无。源码已说明 dry-run 不需要 `--yes`。空名单 = 无合格非近期候选，不是 EOF。

### 风险与回退

- 风险：执行漏 `--yes` 被 mole 拒绝；或误以为预览必须 `--yes`
- 回退：预览/执行两套 argv 工厂，单测锁死

### 依赖与约束

- 依赖 t008

### Finalization 时更新的 blueprint

- 无
