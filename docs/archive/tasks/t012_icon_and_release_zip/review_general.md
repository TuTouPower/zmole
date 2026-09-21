# Task review t012（reviewer_focus: 通用）

- task：`t012_icon_and_release_zip`
- spec：`docs/tasks/t012_icon_and_release_zip/spec.md`
- diff_anchor：`c11ed2b18ef3db579c95970ea38eaa73cd55401c`
- target：`git -C '/Users/karson/kar/code/zmole_t012' diff c11ed2b18ef3db579c95970ea38eaa73cd55401c`
- round：1
- reviewed_at：2026-09-22 05:52 UTC+8

reviewed_scope: e148622472d38a36

## Findings

### t012_gen_f001 - 交付图标与 Info.plist 文件未进入当前评审 diff

- 严重度：important
- 锚点：评审完整性缺陷；当前完整交付无法确认
- 位置：`src/zmole/Info.plist:1`、`src/zmole/Resources/AppIcon.icns`、`assets/app_icon_source.png`
- 问题：`git status --short --untracked-files=all` 仍显示上述三个交付文件为 `??`；相对 anchor 的 `git diff` 只包含 `project.pbxproj`、`project.yml` 和流程文件，因此 reviewer 无法把图标二进制与 Info.plist 纳入当前 patch 审查，也无法证明它们会进入执行 commit。即使工作树中可以直接读取文件，仍违反本 review prompt 对未跟踪交付文件的完整性门禁，结论必须为 INCOMPLETE。
- 建议：实施方先对三个明确的新交付文件执行 `git add -N` 使其进入评审 diff；修复其余问题后重新生成 scope 并重跑 single review，最终提交时确认三文件已实际加入 commit。

### t012_gen_f002 - 自定义 Info.plist 生成出不完整的 macOS application bundle

- 严重度：important
- 锚点：行为缺陷；构建产物缺少 application bundle 基础元数据，影响 Finder/LaunchServices 及下载后启动路径
- 位置：`project.yml:39-41`、`src/zmole/Info.plist:4-10`
- 问题：改动关闭 `GENERATE_INFOPLIST_FILE` 并指定自定义 plist，但该 plist 只声明 `CFBundleDisplayName`、`CFBundleIconFile` 和 `LSApplicationCategoryType`。独立执行 `xcodebuild -project Zmole.xcodeproj -scheme Zmole -configuration Debug -derivedDataPath .scratch/review_derived build` 后，产物 `Contents/Info.plist` 缺少 `CFBundleIdentifier`、`CFBundlePackageType`、`CFBundleExecutable`、`CFBundleVersion`、`CFBundleShortVersionString`，`Contents/PkgInfo` 为 `????????`。图标文件虽已复制到 `Contents/Resources/AppIcon.icns`，但最终 app bundle 元数据不完整，不能作为正常可分发 application bundle 验收。
- 建议：在自定义 plist 中补齐标准 bundle 键并使用 build setting 展开值，或保留生成 plist 并以不覆盖生成元数据的方式注入 `CFBundleIconFile`；重新构建后检查产物 plist 与 `PkgInfo`。

## 结论

- 前轮 finding 复核：无，single Round 1。
- 本轮新发现：2 条。
- 未进表的提示：已扫过规格、实现、资源、bundle contract、异常路径、性能与资源、架构可维护性、安全、测试与文档一致性；未发现其他需要入表问题。图标视觉为抽象 Z/工具形，未观察到 Mole 地鼠官方造型模仿。README 三条 Gatekeeper 路径存在于当前 README，但 README 不在本 task 相对 anchor 的业务 diff 中。
- AC 复验方式：
    - AC-001：re_verified。独立 Debug 构建成功；产物包含 `Contents/Resources/AppIcon.icns`，且产物 `Info.plist` 的 `CFBundleIconFile` 为 `AppIcon.icns`，资源与源文件字节一致。未在 Finder/Dock 中执行人工渲染检查。
    - AC-002：re_verified。独立读取 README 第 20–25 行，确认同时包含右键「仍要打开」、系统设置「仍要打开」与 `xattr -cr`。
    - coverage = 2 / 2
- 总体判断：AC 文案与图标资源路径可见，但未跟踪交付文件及不完整的 application bundle 元数据仍是重要问题，当前不能通过最终评审。
- 系统性 follow-up：无。

## Round 2 (2026-09-22 05:56 UTC+8)

reviewed_scope: e1fca68d7ddf791c

## Findings

本轮无新 finding。

## 结论

- 前轮 finding 复核：`t012_gen_f001` 已消除。三个交付文件已通过 intent-to-add 纳入相对 anchor 的完整 diff，`git diff --summary` 已显示 `assets/app_icon_source.png`、`src/zmole/Info.plist`、`src/zmole/Resources/AppIcon.icns` 的新增内容。
- `t012_gen_f002` 修复不彻底，仍存在。基于当前完整 diff 重新执行 `xcodebuild -project Zmole.xcodeproj -scheme Zmole -configuration Debug -derivedDataPath .scratch/review_derived_r2 build` 成功，`Contents/PkgInfo` 已从前轮的 `????????` 变为 `APPL????`；但产物 `Contents/Info.plist` 仍缺少 `CFBundleIdentifier`、`CFBundleExecutable`、`CFBundleVersion`、`CFBundleShortVersionString`，源文件 `src/zmole/Info.plist:4-15` 也未声明这些基础 bundle 键。原 finding 指出的 application bundle 元数据不完整问题未完全消除。
- 本轮新发现：0 条。
- 未进表的提示：已复核规格、图标资源接入、bundle 元数据、异常路径、安全、性能与资源、架构可维护性、测试和文档一致性；未发现其他需要入表问题。图标资源与构建产物字节一致；图标视觉仍为抽象 Z/工具形，未观察到 Mole 地鼠官方造型模仿。
- AC 复验方式：
    - AC-001：`re_verified`。独立构建成功；产物包含 `Contents/Resources/AppIcon.icns`，与 `src/zmole/Resources/AppIcon.icns` 比对一致，产物 `Info.plist` 的 `CFBundleIconFile` 为 `AppIcon.icns`。
    - AC-002：`re_verified`。独立读取 `README.md:20-25`，确认包含右键打开、系统设置「仍要打开」和 `xattr -cr`。
    - coverage = 2 / 2
- 总体判断：前轮未跟踪文件问题已消除，PkgInfo 的全问号问题已修复；application bundle 仍缺少基础元数据，`t012_gen_f002` 这个 important finding 仍阻断通过。
- 系统性 follow-up：无。

verdict: FAIL

## Round 3 (2026-09-22 05:59 UTC+8)

reviewed_scope: f184f55dd399a8b8

## Findings

本轮无新 finding。

## 结论

- 前轮 finding 复核：`t012_gen_f001` 已消除。三个交付文件已通过 intent-to-add 纳入相对 anchor 的完整 diff，`git diff --summary` 可见 `assets/app_icon_source.png`、`src/zmole/Info.plist`、`src/zmole/Resources/AppIcon.icns`。
- `t012_gen_f002` 已消除。独立执行 Debug 构建成功；产物 `Contents/Info.plist` 含 `CFBundleIdentifier=com.tutupower.zmole`、`CFBundleExecutable=Zmole`、`CFBundlePackageType=APPL`、`CFBundleVersion=1`、`CFBundleShortVersionString=1.0`，`Contents/PkgInfo` 为 `APPL????`。
- 本轮新发现：0 条。
- 未进表的提示：已复核规格、实现、资源、bundle 元数据、异常路径、安全、性能与资源、架构可维护性、测试和文档一致性；未发现其他需要入表问题。图标资源已复制到产物 `Contents/Resources/AppIcon.icns`，与源文件字节一致。图标视觉为抽象 Z/工具形，未观察到 Mole 地鼠官方造型模仿。
- AC 复验方式：
    - AC-001：`re_verified`。独立运行 `xcodebuild ... Debug ... build` 成功；产物含 `Contents/Resources/AppIcon.icns`，源与产物字节一致，产物 `Info.plist` 的 `CFBundleIconFile` 为 `AppIcon.icns`。未在 Finder/Dock 执行人工渲染检查。
    - AC-002：`re_verified`。独立读取 `README.md:20-25`，确认同时包含右键「仍要打开」、系统设置「仍要打开」与 `xattr -cr`。
    - coverage = 2 / 2
- 总体判断：前轮完整 diff 与 application bundle 元数据问题均已消除，AC-001/AC-002 通过复验。
- 系统性 follow-up：无。

verdict: PASS
