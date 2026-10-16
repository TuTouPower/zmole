# Task review t033（reviewer_focus: 通用）

- task：`t033_replace_app_logo`
- spec：`docs/tasks/t033_replace_app_logo/spec.md`
- diff_anchor：`03580b8fd999c141509e07e30ecbee17deb051a5`
- target：`git -C '/Users/karson/kar/code/zmole_t033' diff 03580b8fd999c141509e07e30ecbee17deb051a5`
- round：1
- reviewed_at：2026-10-17T03:11:36+08:00

reviewed_scope: a0273189b3b3d632

## Findings

### t033_gen_f001 - 测试 helper 吞掉子进程 stderr，失败时缺关键诊断

- 严重度：minor
- 锚点：行为缺陷（可观测性）：生成脚本在测试环境失败时，断言不携带失败原因
- 位置：`tests/unit/AppIconTests.swift:107`
- 问题：`run()` 把子进程 stdout/stderr 全部指向 `FileHandle.nullDevice`。`testAppIconIsRegenerableFromTheTrackedSource` 依赖 `scripts/build_app_icon.sh` 子进程；若 qlmanage 在无 GUI 会话渲染不出 PNG、或 iconutil 报错，断言只输出 `"…/build_app_icon.sh failed"`，脚本自身写到 stderr 的关键信息（如 `qlmanage produced no render for …`）被丢弃，跨机/换环境复现时无法定位。
- 建议：用 `Pipe` 捕获 stderr，把尾部若干行并入 `XCTAssertEqual` 的 message。

## 结论

- 前轮 finding 复核（Round N≥2 才写）：首轮，无。
- 本轮新发现：1 条（minor）。
- 未进表的提示：
    - `scripts/build_app_icon.sh:27` 的 `find "$WORK" -maxdepth 1 -name '*.png' | head -1` 在 `set -o pipefail` 下理论上可被 SIGPIPE 波及；当前单输入场景 qlmanage 只产出一个 PNG，失败路径不可达，不构成 finding。
    - 新测试对 qlmanage（GUI 会话）+ Xcode 工具链有环境依赖；本机 Xcode 26.6 全绿。仓库当前无 CI 配置，若未来引入无头 CI 需重估此测试。
    - task.md 声称的黑盒 demo 启动截图在 worktree（含 `.scratch`）中无图片产物可查，不能作为证据采信，见下方 AC-003 trust_prior。
- 总体判断：四条 AC 均有实现与可复现佐证（含源→icns 字节级复现），全量 241 测试通过且经独立复跑，无未解决 critical/important，仅 1 条 minor。
- 系统性 follow-up：无

### AC 复验方式

- AC-001 re_verified：`assets/app_icon_source.svg`（彩色，含 linearGradient）与 `app_icon_source_mono.svg` 均以 100% 相似 rename 入库；`git status` 与仓库根均无 gemini SVG 残留、无未跟踪交付文件。
- AC-002 re_verified：新旧 icns sha 不同（`3e5608ef…` → `122ae945…`）；独立重跑 `scripts/build_app_icon.sh` 输出与 shipped icns `cmp` 字节一致；iconutil 回解出 16/32/64/128/256/512/1024 共 10 档；Debug 构建产物 `Zmole.app/Contents/Resources/AppIcon.icns` 同 sha，512px 像素采样为高饱和彩色渐变渲染（非空白），证明源出彩色主版 SVG。
- AC-003 trust_prior：Finder/Dock/侧栏真实渲染为人工 UI 确认（`[deploy]`），依赖实施侧 task.md 的截图声明，仓库内无截图产物。其静态替代本审已复验：`src/zmole/App/SidebarView.swift:47` 经 `NSApp.applicationIconImage` 取 bundle 图标、`src/zmole/Info.plist` `CFBundleIconFile=AppIcon.icns`、`project.yml:35` 资源引用，构建产物 icns 与源一致。
- AC-004 re_verified：全仓 grep `app_icon_source.png` 无构建引用（仅 `docs/archive/` 历史文档提及）；`assets/app_icon_source.png` 已删除；`project.yml`/`Info.plist`/pbxproj 均无旧源引用。
- coverage = 3 / 4

verdict: PASS

## Round 2 (2026-10-17T03:14:59+08:00)

reviewed_scope: 52d8c267f2b2c157

### 前轮 finding 复核

- t033_gen_f001（minor，测试 helper 吞 stderr）：**已消除**。`tests/unit/AppIconTests.swift:102-119` 的 `run()` 改为 `Pipe()` 捕获 stderr，`readDataToEndOfFile()` 后取 `suffix(2_048)` 尾部并入失败断言消息；`XCTAssertEqual(process.terminationStatus, 0, …)` 断言强度未变。独立复验：微程序（`/bin/bash` 写 stderr 后 exit 3）确认「先读 Pipe 再 waitUntilExit」模式无死锁且取到 `err-line`；AppIconTests 5/5 通过；全量 241 测试 0 失败。除该文件与 task.md 外，其余交付文件（脚本、icns、SVG、conventions、pbxproj）相对 Round 1 逐字节未变。

### 本轮新发现

0 条。

### 未进表的提示

- `run()` 的 `readDataToEndOfFile()` 先于 `waitUntilExit()`；仅当被测进程派生出继承 stderr 且长于脚本存活的后台孙进程时才会阻塞。当前各工具（qlmanage/sips/iconutil）随脚本退出即关闭写端，未构成问题。
- 余同 Round 1 未进表提示（`find | head -1` 在 pipefail 下不可达的 SIGPIPE 脆弱性、新测试的 qlmanage GUI 会话依赖、黑盒截图无仓库产物）。

### AC 复验方式

- AC-001 re_verified：本轮 `git status`/diff 复核，源文件落位与根目录清理未变（fix 仅触 `tests/unit/AppIconTests.swift`）。
- AC-002 re_verified：本轮重跑 `testAppIconIsRegenerableFromTheTrackedSource` 通过（新 helper 下脚本重渲染仍与 shipped icns 字节一致）；icns sha 仍为 `122ae945…`，与旧 `3e5608ef…` 不同。
- AC-003 trust_prior：未变，仍依赖实施侧人工/截图确认；仓库内无截图产物。
- AC-004 re_verified：本轮重跑 `testNoStaleIconSourceReferences` 通过；`project.yml`、`Info.plist`、脚本相对 Round 1 未改动。
- coverage = 3 / 4

verdict: PASS
