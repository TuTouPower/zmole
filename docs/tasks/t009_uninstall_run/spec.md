# Task spec

## 背景

`uninstall --list` 在非 TTY 下为 JSON。按名称卸载的路径仍有 `[y/N]` 行确认（`uninstall.sh` 约 1767 行），dry-run 也经过该点。空 stdin 会 `Aborted`（exit 非 0）。stdin 写入 mole 文档化的 `y\n` 后，后续 `read -n1` 遇 EOF 视为 Enter，dry-run 能跑完。这不是驱 TUI（无 PTY、无方向键、不解析画面）。

`match_apps_by_name` 对每个搜索词取**第一个**显示名或 `.app` 目录基名精确匹配，否则子串匹配。`uninstall_name` 不是路径级主键。同名不同目录时，CLI 无法保证卸到勾选的那一份。

## 契约区

### 范围

- `--list` 展示已装 App；勾选。列表行身份 = `path` + `bundle_id` + `uninstall_name`
- 预览：仅当所选行的 `uninstall_name` 在**当前 list 结果**中唯一，才 spawn `uninstall --dry-run <uninstall_name>`，stdin 固定为 `y\n`
- 确认后：同样唯一性约束下 spawn `uninstall <uninstall_name>`（无 `--dry-run`），stdin 同样 `y\n`
- 默认废纸篓路径，不传 `--permanent`
- 预览失败、取消、勾选变化、目标 path 消失或 `uninstall_name` 变得不唯一：禁止执行，须重新预览
- 执行结果（stdout 摘要 / 非零退出）展示在页面上
- 复用 t008 的预览新鲜度与执行生命周期规则

### 非范围

- 无参数交互 TUI；永久删除开关；PTY / 方向键 / 解析 TUI 帧
- 无法在 CLI 层按 path 消歧时，不自行 `rm` / 不绕过 mole

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：`--list` 夹具 JSON 展示 `name`、`uninstall_name`、`path`、`bundle_id`
- [ ] AC-002：预览 argv 含 `--dry-run` 与所选行的 `uninstall_name`；stdin 为恰好 `y\n`
- [ ] AC-003：未确认时不 spawn 不含 `--dry-run` 的 uninstall
- [ ] AC-004：任何生产调用的 uninstall argv 不含 `--permanent`
- [ ] AC-005：未选择任何 App 时不能发起预览或执行
- [ ] AC-006：确认后发起无 `--dry-run` 的 uninstall（stdin `y\n`），页面展示成功摘要或失败文案
- [ ] AC-007：同一 list 中两条 `uninstall_name` 相同、`path` 不同时，禁止预览与执行，并说明无法唯一匹配
- [ ] AC-008：预览后勾选改为另一 App，确认按钮不可用，直到对新勾选重新预览成功
- [ ] AC-009：预览成功后，再 list 发现所选 `path` 消失或落到不同 `path`，禁止执行
- [ ] AC-010：预览时 stdin 为空的假 mole 返回非 0 / `Aborted` 时，视为预览失败，禁止执行
- [ ] AC-011：遵守 t008 的忙碌/取消/失败：执行中不可再点执行；取消终止该 Process

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- 全部 AC 可自动测试（假 Bridge / 夹具 list；不真卸本机 App）

## 上下文区

- 来源：审阅 P1；实测 `uninstall --dry-run 'Scroll Reverser'`：空 stdin exit 1 停在 `[y/N]`；`y\n` dry-run 完整列出将删路径。匹配逻辑见 `bin/uninstall.sh` `match_apps_by_name`

### 有意不测

- 真卸载本机 App：不测
- 子串误匹配的全表扫描：用夹具覆盖同名与唯一名即可

### 测试策略

- 夹具 list JSON + spy argv **与 stdin**
- 同名 / 目标消失 / 勾选变更 / 预览失败 用 ViewModel 状态测

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无。命名 dry-run 的 `[y/N]` 与 `y\n` 协议已用锁定源码 + 一次 dry-run 实测。list 字段见 s001。

### 风险与回退

- 风险：把 `uninstall_name` 当主键卸错 App；空 stdin 假绿
- 回退：执行前用当前 list 校验 `path`+`bundle_id`+唯一 `uninstall_name`；Bridge 单测断言 stdin

### 依赖与约束

- 依赖 t008；stdin 协议见 `docs/blueprint/architecture.md`「卸载确认协议」

### Finalization 时更新的 blueprint

- `docs/blueprint/architecture.md`：若实现细节与本文不一致，以实现回写协议段落
