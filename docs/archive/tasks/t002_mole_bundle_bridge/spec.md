# Task spec

## 背景

第一版开箱即用，不要求用户安装 Homebrew `mo`。运行时只 spawn 捆绑的钉死版本 mole。产品要求 Universal：主程序与 Go helper 都必须是 arm64+x86_64。

## 契约区

### 范围

- 将 mole **tag `V1.55.0` / commit `69ab325d`** 的安装树打进 `Contents/Resources/mole/`（Bash 树与 Go helper 同一 tag，不用研究仓 `main`）
- Go helper：该 tag Release 的 `analyze-darwin-arm64`/`amd64` 与 `status-darwin-*`，以 `bin/analyze-go`、`bin/status-go` 交付，且均为双架构（lipo 或运行时按 arch 选择，Release 包内两种芯片都能跑）
- `MoleBridge`：绝对路径定位入口、`async` 跑 `Process`、超时、取消（杀进程组）、捕获 stdout/stderr/exit、可注入 stdin
- 每个调用方最多一个 in-flight 进程；忙碌时拒绝第二次 `run`（返回明确忙碌错误，不新开进程）
- 至少能跑 `--version` 并给 UI 用
- 单测用假可执行夹具，不依赖本机 brew `mo`

### 非范围

- 功能页、把 CLI 装进 PATH、调用 `update`/`remove`、解析 TUI、PTY

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：Debug `.app` 内存在捆绑 mole 入口文件；Bridge 解析到的路径位于该 `.app` bundle 内
- [ ] AC-002：Bridge 执行 `--version` 成功时返回非空版本字符串；失败时返回可展示错误，不崩溃
- [ ] AC-003：假二进制夹具测试覆盖：成功输出、非零退出、超时取消（进程已结束）；断言命令行参数、工作目录、stdin 字节
- [ ] AC-004：生产 Bridge **不**搜索 `/opt/homebrew/bin/mo` 或 `PATH` 作为默认入口
- [ ] AC-005：资源文件能读到捆绑 mole 的上游 tag `V1.55.0` 与 commit `69ab325d`
- [ ] AC-006：`file`/`lipo -archs` 显示 App 可执行文件、`bin/analyze-go`、`bin/status-go` 均含 `x86_64` 与 `arm64`（或等价的双切片布局且在两种 arch 的机器上能选中对应切片）
- [ ] AC-007：in-flight 时第二次 `run` 不创建新 Process，并返回忙碌错误
- [ ] AC-008：对已启动的假长进程调用 `cancel` 后，该 PID 不复存在

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001、AC-006：构建后脚本检查产物
- AC-002：对捆绑 mole 集成
- AC-003、AC-004、AC-007、AC-008：单元测试
- AC-005：读资源文件

## 上下文区

- 来源：ADR-002、ADR-005；审阅 P1 Universal / P2 生命周期；s001 披露研究仓 `0659e906` 与 tag `69ab325d` 不是同一快照

### 有意不测

- mole 内部清理正确性：不测

### 测试策略

- 假二进制单测生命周期；产物用 `lipo -archs`

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无。Release `V1.55.0` 已提供分 arch 的 analyze/status 二进制。

### 风险与回退

- 风险：漏拷 `lib/`；只 lipo 了 App 没 lipo helper
- 回退：整树复制；AC-006 卡发布

### 依赖与约束

- 依赖 t001；GPL：源码链接指向 `V1.55.0` / `69ab325d`

### Finalization 时更新的 blueprint

- `docs/blueprint/architecture.md`：实际 bundle 相对路径与入口文件名
