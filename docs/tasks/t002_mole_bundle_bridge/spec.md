# Task spec

## 背景

第一版开箱即用，不要求用户安装 Homebrew `mo`。运行时只 spawn 捆绑的钉死版本 mole。

## 契约区

### 范围

- 将 mole（目标上游 tag `V1.55.0`，以本仓记录的 commit 为准）安装树打进 `Contents/Resources/mole/`
- `MoleBridge`：绝对路径定位入口、`async` 跑 `Process`、超时、取消、捕获 stdout/stderr/exit
- 至少能跑 `--version` 并给 UI 用
- 单测用假可执行夹具，不依赖本机 brew `mo`

### 非范围

- 功能页、把 CLI 装进 PATH、调用 `update`/`remove`、解析 TUI

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：Debug `.app` 内存在捆绑 mole 入口文件；Bridge 解析到的路径位于该 `.app` bundle 内
- [ ] AC-002：Bridge 执行 `--version` 成功时返回非空版本字符串；失败时返回可展示错误，不崩溃
- [ ] AC-003：假二进制夹具测试覆盖：成功输出、非零退出、超时取消；断言命令行参数与工作目录符合封装
- [ ] AC-004：生产 Bridge **不**搜索 `/opt/homebrew/bin/mo` 或 `PATH` 作为默认入口
- [ ] AC-005：README 或关于页数据能读到捆绑 mole 的上游 tag/commit（实现可先提供 API，UI 可在 t003 接）

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001：构建后检查产物路径，可自动或脚本
- AC-002：可对真实捆绑 mole 集成；无 Go 构建时用预置 fixture 二进制 skip 并在 handoff 说明
- AC-003、AC-004：单元测试
- AC-005：读源码或资源文件

## 上下文区

- 来源：ADR-002；`docs/plan.md`

### 有意不测

- mole 内部清理正确性：不测

### 测试策略

- 假二进制单测为主；可选集成 `--version`

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- Universal 下 Go 辅助程序如何打进 bundle：`UNVERIFIED-SPIKE`，用 `s001` 或本 task 内验证 `make release-arm64`/`release-amd64` 布局；失败则先只打本机 arch 并在 handoff 记录

### 风险与回退

- 风险：mole 不是单文件，漏拷 `lib/` 会导致子命令失败
- 回退：按上游 install 布局整树复制，入口用绝对路径

### 依赖与约束

- 依赖 t001；GPL：本仓记录对应源码 tag，不把源码打进 zip

### Finalization 时更新的 blueprint

- `docs/blueprint/architecture.md`：实际 bundle 相对路径与入口文件名
