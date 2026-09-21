# Task spec

## 背景

确认后的第一版需要可构建的 macOS SwiftUI 工程。禁止手写损坏的 pbxproj。

## 契约区

### 范围

- 根目录 `project.yml`，用 XcodeGen 生成 `Zmole.xcodeproj`
- macOS 13+，Universal，SwiftUI 窗口 + `NavigationSplitView` 占位侧栏
- 单测 target；ad-hoc 签名
- 更新 `docs/blueprint/testing.md` 的 `doctor_cmd` / `test_cmd` 接入 `xcodebuild`

### 非范围

- 捆绑 mole、功能页、图标定稿、公证

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：在已切到 Xcode.app 的机器上，`xcodegen` 后 `xcodebuild -scheme Zmole -configuration Debug -destination 'platform=macOS' build` 退出码 0，产物为 `.app`
- [ ] AC-002：启动 App 可见侧栏占位项，点击切换内容区占位文字，不崩溃
- [ ] AC-003：`xcodebuild test -scheme Zmole -destination 'platform=macOS'` 退出码 0（允许仅有空/样例测试）
- [ ] [deploy] AC-004：`testing.md` 的 `doctor_cmd` 含 `xcodebuild -version` 与 `xcodegen --version`；`test_cmd` 含上述 test 命令且仍跑模板 pytest
- [ ] AC-005：`ARCHS`/`ONLY_ACTIVE_ARCH` 配置为 Universal；对 Debug `.app` 主可执行文件 `lipo -archs` 含 `x86_64` 与 `arm64`

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001、AC-003、AC-005：可自动
- AC-002：UI 手工；无 UI 测试时 `[deploy]` 记录截图或步骤
- AC-004：读 `testing.md` + 跑 doctor/test 命令

## 上下文区

- 来源：`docs/plan.md`（2026-09-21 确认）

### 有意不测

- Xcode GUI 点击生成工程：不测；只测 XcodeGen CLI 路径

### 测试策略

- 构建与 test target 为门禁；侧栏切换手工

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无

### 风险与回退

- 风险：本机 `xcode-select` 仍指向 CLT 则 doctor 失败
- 回退：文档写明切 Xcode.app；不提交半截 pbxproj

### 依赖与约束

- 需要完整 Xcode 与 XcodeGen

### Finalization 时更新的 blueprint

- `docs/blueprint/testing.md`：doctor_cmd / test_cmd
- `docs/blueprint/conventions.md`：工程生成命令
