# 测试

模板仓默认门禁命令（复制新项目后按实际工具链替换）。章节名 `doctor_cmd` / `test_cmd` / `blackbox_verify` 是 preflight 与 skill 的机械锚点，不得改名；命令写在对应章节正文。未使用某类时章节保留，正文写「无」。

下列默认命令在消费仓根的 POSIX shell（macOS）执行。任一检查非零退出则停止后续验收。

## doctor_cmd

环境前置检查：模板工具链可收集；`md_kx` 在 PATH。完整 Xcode（含 `xcodebuild`）在工程落地后纳入本检查；当前本机若仅有 Command Line Tools，不在此硬失败。

```bash
pytest .repo_template/tests -q --collect-only -m contract
command -v md_kx
xcodebuild -version
xcodegen --version
xcodegen generate
```

## test_cmd

日常测试（红/绿）。Xcode 工程与单测 target 落地前，业务侧写「无」；落地后改为：

```bash
xcodegen generate
xcodebuild test -scheme Zmole -destination 'platform=macOS'
pytest .repo_template/tests -q -m contract
```

当前阶段以模板工具链测试为主；业务 Swift 测试随首个实现 task 接入本命令。填本命令时按「门禁类别清单」逐类覆盖；项目不适用某类写「无」并说明理由。

## blackbox_verify

演示 UI smoke（不启动真实 mole）：

```bash
DEMO_ROOT="$PWD/.scratch/ui_rebuild/demo_data"
mkdir -p "$DEMO_ROOT"
open -a Zmole --args --demo --demo-page analyze --demo-state populated \
  --demo-language zh-Hans --demo-appearance light --demo-data-root "$DEMO_ROOT"
```

打开后检查 Analyze 生产页面显示 fixture；进入 Software → Protection rules 并保存、或执行 Clean preview 后，再检查对应文件只出现在 `DEMO_ROOT`。截图验收覆盖 1200×760 与 880×620、浅/深色和三语。

Status read-only watch 验证：

```bash
xcodebuild test -scheme Zmole -destination 'platform=macOS' \
  -only-testing:ZmoleTests/StatusStreamTests
```

该测试仅使用 streaming fixture，验证首帧渐进字段、暂停/恢复、离页停止、断流和磁盘 I/O warming；不调用真实 mole。真实只读黑盒路径由 Bridge 层以 `status --json` / `status --watch` 夹具验证，禁止将破坏性命令纳入 blackbox smoke。

真实只读黑盒仅允许检测捆绑入口并运行 `--version`、`status --json` 等命令；破坏性命令只用 dry-run 或测试夹具。Demo smoke 不得检测或启动 PATH 中的 `mo`。

## Release zip

发布脚本：

```bash
./scripts/build_release_zip.sh
```

脚本只构建 Release、验证 ad-hoc 签名并输出 `artifacts/releases/Zmole-<version>.zip`。发布验收还需解压后检查主程序与 `mole/bin/analyze-go`、`status-go` 的 Universal 架构，并对解压 App 运行 status、history、analyze 只读流程。

## Schema / codegen 验证

无

本项目暂无 codegen / DB migration。若增加 `schemas/mole_cli` 校验脚本，在此登记生成与验证命令。

## 门禁类别清单

|类别|必须覆盖|常见盲区|
|---|---|---|
|单元测试|Bridge 参数、JSON/文本解析、ViewModel 状态|mock 掉被测逻辑、断言过弱（假绿）|
|生产代码类型检查|Swift 编译通过（`xcodebuild build`）|仅编译改动文件、忽略 App 入口|
|测试代码类型检查|测试 target 编译通过|测试 helper 类型漂移|
|lint|SwiftLint（若引入）或「无」并说明|只查改动文件、存量无限积累|
|生产构建|`xcodebuild -configuration Release build`|签名/公证配置与 Debug 不一致|
