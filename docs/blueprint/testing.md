# 测试

模板仓默认门禁命令（复制新项目后按实际工具链替换）。章节名 `doctor_cmd` / `test_cmd` / `blackbox_verify` 是 preflight 与 skill 的机械锚点，不得改名；命令写在对应章节正文。未使用某类时章节保留，正文写「无」。

下列默认命令在消费仓根的 POSIX shell（macOS）执行。任一检查非零退出则停止后续验收。

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
```

门禁按「门禁类别清单」逐类覆盖；业务 Swift 单测与三条集成脚本均已接入本命令。

## blackbox_verify

演示 UI smoke（不启动真实 mole）：

```bash
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

## Release zip

发布脚本：

```bash
./scripts/build_release_zip.sh
```

脚本只构建 Release、校验 `Zmole Local Signing` 签名并输出 `artifacts/releases/Zmole-<version>.zip`。发布验收还需解压后检查主程序与 `mole/bin/analyze-go`、`status-go` 的 Universal 架构，并对解压 App 运行 status、history、analyze 只读流程。

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
