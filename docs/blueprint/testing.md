# 测试

本项目门禁命令按 macOS SwiftUI 工具链配置。章节名 `verification_policy` / `verification_notes` / `doctor_cmd` / `test_cmd` / `blackbox_verify` 是 preflight 与 skill 的机械锚点，不得改名；命令写在对应章节的唯一 bash/sh 块，示例与说明改用 `text` 围栏或正文。未使用某类门禁时整节正文恰写「无」，理由记入 `verification_notes`。

下列默认命令在消费仓根的 POSIX shell（macOS）执行。任一检查非零退出则停止后续验收。

## verification_policy

project_configured

## verification_notes

本项目已按 macOS SwiftUI 应用配置验证范围。`verification_policy` 取 `project_configured`；doctor_cmd / test_cmd / blackbox_verify 的命令由本仓脚本与 Xcode 工具链执行，模板同步只校验其格式并跑模板契约测试，不代跑业务门禁。

实际验证范围：doctor_cmd 校验契约用例可收集（`pytest .repo_template/tests -q --collect-only -m contract`）、`md_kx`、完整 Xcode（`xcodebuild -version`）、XcodeGen、`Zmole Local Signing` 签名身份与图标单测依赖（bash/swift/sips/iconutil），并执行 `xcodegen generate`；test_cmd 以 `xcodebuild test -scheme Zmole -destination 'platform=macOS'` 跑全量 Swift 单测，接 `pytest .repo_template/tests -q -m contract` 模板契约，再依次跑四条集成脚本（clean_trash、installer_interface、uninstall_stream、brew_cask_index）覆盖 Bridge/CLI 集成；blackbox_verify 保留 `ZmoleTests/StatusStreamTests` 的 streaming fixture 行为验证。

不适用门禁与理由：

- 无独立真实 CLI 黑盒自动化门禁：zmole 为 GUI 应用，捆绑 mole CLI；真实只读黑盒仅允许 `--version`、`status --json` 等命令，破坏性命令按约定只用 dry-run 或测试夹具，禁止纳入 blackbox smoke，也不得检测或启动 PATH 中的 `mo`。Demo UI smoke 与截图为人工视觉验收（证据存 `docs/guides/visual_acceptance/`），命令仅作 `text` 示例不作为 bash 门禁。
- lint 未引入 SwiftLint（「门禁类别清单」记为「无」）；Swift 类型检查与测试 target 编译由 `xcodebuild` 全量编译覆盖，不单列静态检查命令。
- 无 codegen / DB migration（Schema / codegen 验证章节记为「无」）。
- 生产 Release 构建、签名与 Universal 架构校验由 `./scripts/package_app.sh`（Release app 章节）在发布时执行，不并入日常 doctor/test 门禁。

## doctor_cmd

环境前置检查：模板工具链可收集；`md_kx` 在 PATH；完整 Xcode（`xcodebuild`）与 XcodeGen 为当前门禁必需项。签名身份 `Zmole Local Signing` 为构建/发布必需，缺失时先跑 `./scripts/setup_signing_identity.sh` 一次性创建。图标单测还依赖 `bash`、`swift`、`sips`、`iconutil`（见 `AppIconTests`）。

```bash
pytest .repo_template/tests -q --collect-only -m contract
command -v md_kx
xcodebuild -version
xcodegen --version
security find-identity -v -p codesigning | /usr/bin/grep -qF "Zmole Local Signing"
xcodegen generate
```

## test_cmd

日常测试（红/绿）：

```bash
xcodegen generate
xcodebuild test -scheme Zmole -destination 'platform=macOS'
pytest .repo_template/tests -q -m contract
bash tests/integration/clean_trash_test.sh
bash tests/integration/installer_interface_test.sh
bash tests/integration/uninstall_stream_test.sh
bash tests/integration/brew_cask_index_test.sh
```

门禁按「门禁类别清单」逐类覆盖；业务 Swift 单测与四条集成脚本均已接入本命令。

## blackbox_verify

演示 UI smoke（人工视觉验收，不作自动化门禁；命令为 `text` 示例）：

```text
DEMO_ROOT="$PWD/.scratch/ui_rebuild/demo_data"
mkdir -p "$DEMO_ROOT"
open -a Zmole --args --demo --demo-page disk --demo-state populated \
  --demo-language zh-Hans --demo-appearance light --demo-data-root "$DEMO_ROOT"
```

打开后检查 Disk 生产页面显示 fixture；进入设置 → 保护规则并保存、或执行 Clean preview 后，再检查对应文件只出现在 `DEMO_ROOT`。截图验收覆盖 1200×780 与 1100×700、浅/深色和三语。

Status read-only watch 验证：

```bash
xcodebuild test -scheme Zmole -destination 'platform=macOS' \
  -only-testing:ZmoleTests/StatusStreamTests
```

该测试仅使用 streaming fixture，验证首帧渐进字段、零值、网络聚合、共享流与有界趋势、断流重试与 pause/stop 取消底层流；不调用真实 mole。真实只读黑盒路径由 Bridge 层以 `status --watch` 夹具验证，禁止将破坏性命令纳入 blackbox smoke。

真实只读黑盒仅允许检测捆绑入口并运行 `--version`、`status --json` 等命令；破坏性命令只用 dry-run 或测试夹具。Demo smoke 不得检测或启动 PATH 中的 `mo`。

视觉验收截图证据存放于 `docs/guides/visual_acceptance/`（按 `<语言>_<外观>_<尺寸>_<页面>.png` 命名，附 README 说明构建版本、覆盖范围与已知边界）。

## Release app

发布/打包脚本：

```bash
./scripts/package_app.sh
```

脚本构建 Release、产物直接输出至 `artifacts/mac-arm64/Zmole.app`（按架构），就地校验 `Zmole Local Signing` 签名并自动维护 `/Applications/Zmole.app` 软链接。发布验收需检查主程序与 `mole/bin/analyze-go`、`status-go` 的 Universal 架构，并对 App 运行 status、history、analyze 只读流程。支持传入 `--run` 直接启动。

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
