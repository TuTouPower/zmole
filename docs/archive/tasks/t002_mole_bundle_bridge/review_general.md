# Task review t002（reviewer_focus: 通用）

- task：`t002_mole_bundle_bridge`
- spec：`docs/tasks/t002_mole_bundle_bridge/spec.md`
- diff_anchor：`c7d06d7d6e9726c0ac831a9fce5a463e55b7545f`
- target：`git -C '/Users/karson/kar/code/zmole_t002' diff c7d06d7d6e9726c0ac831a9fce5a463e55b7545f`
- round：1
- reviewed_at：2026-09-21 14:12 UTC+8

## Findings

Round 1 零 finding。

独立复核确认：捆绑 Bash 树与 tag 内容一致；helper 来源为同 tag Release 且经 SHA256 校验后合并；XcodeGen folder copy phase 将资源放入正确 bundle 子目录；Bridge 的生产定位路径固定为 bundle resource URL，未使用 PATH 或 Homebrew 路径。

## 结论

- 本轮新发现：0 条。
- 未进表的提示：Xcode 26.6 对 macOS 13.0 XCTest target 输出 XCTest 运行库较新（14.0）的 linker warning；生产 target、测试执行和资源验证均通过。
- 总体判断：实现覆盖 t002 全部范围，未发现未解决的 critical / important 问题。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001：`re_verified`；检查 `project.yml` copy phase、生成 Debug `.app`，确认 `Contents/Resources/mole/mole` 存在且 Bridge locator 指向同一相对路径。
- AC-002：`re_verified`；`MoleBridge.version()` 调用 `--version`，假可执行测试通过，捆绑入口直接返回 `Mole version 1.55.0`。
- AC-003：`re_verified`；`MoleBridgeTests` 覆盖成功输出、参数、工作目录、stdin、非零退出、timeout/cancel，7 个 XCTest 全部通过。
- AC-004：`re_verified`；Bridge 仅接受 bundle locator 或测试注入 executable URL，生产源码无 PATH/Homebrew 默认入口。
- AC-005：`re_verified`；读取 bundle 内 `SOURCE_VERSION`，值为 `V1.55.0` 与完整 commit `69ab325d4f05af0ea21aeeeae544046c9f04a76b`。
- AC-006：`re_verified`；`lipo -archs` 验证 App、`bin/analyze-go`、`bin/status-go` 均输出 `x86_64 arm64`。
- AC-007：`re_verified`；busy 测试第二次调用返回 `.busy`，fixture invocation count 保持为 1。
- AC-008：`re_verified`；cancel 测试验证 fake process PID 退出，timeout 测试同样验证 PID 不存在。

coverage = 8 / 8

verdict: PASS
reviewed_scope: a0ff119c5cb7a770
