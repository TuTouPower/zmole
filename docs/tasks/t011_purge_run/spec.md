# Task spec

## 背景

非 TTY 下真实 purge 必须 `--yes`。无 TTY 的 dry-run 是否卡住由 s001 决定；若卡住则本 task 不得 start，应 park。

## 契约区

### 范围

- 若 s001 表明 dry-run 可返回：展示预览 → 确认 → `purge --yes`
- 执行路径必须带 `--yes`；不存在无 `--yes` 的非 dry-run 调用
- 未确认不 spawn `--yes`

### 非范围

- `purge --paths` 配置 UI；无 `--yes` 的交互选择器

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：预览 argv 含 `purge` 与 `--dry-run`，不含 `--yes`
- [ ] AC-002：执行 argv 含 `purge` 与 `--yes`
- [ ] AC-003：未确认时 `--yes` 调用次数为 0
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

- spy argv；s001 未通过则本 task 保持 backlog 并 park

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无 TTY 下 `purge --dry-run` 是否返回：`UNVERIFIED-SPIKE`，`s001`；**阻塞 start**

### 风险与回退

- 风险：`--yes` 在预览阶段被带上
- 回退：预览/执行两套 argv 工厂，单测锁死

### 依赖与约束

- 依赖 t008；s001 对 purge 的结论为 start 前提

### Finalization 时更新的 blueprint

- 无
