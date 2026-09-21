# 测试

模板仓默认门禁命令（复制新项目后按实际工具链替换）。章节名 `doctor_cmd` / `test_cmd` / `blackbox_verify` 是 preflight 与 skill 的机械锚点，不得改名；命令写在对应章节正文。未使用某类时章节保留，正文写「无」。

下列默认命令在消费仓根的 POSIX shell（macOS）执行。任一检查非零退出则停止后续验收。

## doctor_cmd

环境前置检查：模板工具链可收集；`md_kx` 在 PATH。完整 Xcode（含 `xcodebuild`）在工程落地后纳入本检查；当前本机若仅有 Command Line Tools，不在此硬失败。

```bash
pytest .repo_template/tests -q --collect-only
command -v md_kx
xcodebuild -version
xcodegen --version
```

## test_cmd

日常测试（红/绿）。Xcode 工程与单测 target 落地前，业务侧写「无」；落地后改为：

```bash
xcodegen generate
xcodebuild test -scheme Zmole -destination 'platform=macOS'
pytest .repo_template/tests -q
```

当前阶段以模板工具链测试为主；业务 Swift 测试随首个实现 task 接入本命令。填本命令时按「门禁类别清单」逐类覆盖；项目不适用某类写「无」并说明理由。

## blackbox_verify

无

工程可运行后应补充：启动 App → 检测 `mo` → 对只读命令（如 `mo --version` / `status --json`）跑通并断言 UI 或 Bridge 结果。破坏性命令只用 dry-run 或测试夹具。

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
