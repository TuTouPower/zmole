# Task review t013（reviewer_focus: 通用）

- task：`t013_release_zip_verify`
- spec：`docs/tasks/t013_release_zip_verify/spec.md`
- diff_anchor：`8f12cf619ce86e7dd458013a3f27f05220bc6daf`
- target：`git -C '/Users/karson/kar/code/zmole_t013' diff 8f12cf619ce86e7dd458013a3f27f05220bc6daf`
- round：1
- reviewed_at：2026-09-22 06:21 UTC+8

reviewed_scope: 757300149ff0d7dc

## Findings

### t013_gen_f001 - 自定义相对输出目录从仓库外调用会失败

- 严重度：minor
- 锚点：行为缺陷；脚本公开接受可选输出目录，但相对路径解析前后不一致
- 位置：`scripts/build_release_zip.sh:5,9,24-25`
- 问题：脚本在 `cd "$repo_root"` 前创建相对 `output_dir`，随后在仓库根目录下把同一相对路径传给 `ditto`。从仓库外执行 `scripts/build_release_zip.sh release-output` 时，目录在调用方当前目录创建，打包阶段却查找 `$repo_root/release-output`，最终 zip 创建失败。默认输出目录和仓库根目录下的相对参数已独立复验成功。
- 建议：在切换到仓库根目录前把相对 `output_dir` 解析为绝对路径，或在切换后再创建目录并统一解析基准。

### t013_gen_f002 - ad-hoc 签名校验未检查签名类型

- 严重度：minor
- 锚点：AC-003；当前脚本只验证签名有效，未验证签名为 ad-hoc 或等价本地签名
- 位置：`scripts/build_release_zip.sh:21`；签名配置：`project.yml:17-19`
- 问题：`codesign --verify --deep --strict` 能接受任意有效签名。若工程签名配置后续改为开发证书，脚本仍会通过，无法阻止不符合 AC-003 的发布包。当前构建因 `CODE_SIGN_IDENTITY: "-"` 实际产物显示 `flags=0x2(adhoc)` 和 `Signature=adhoc`，因此本轮不是当前产物失效。
- 建议：在验证命令后检查 `codesign -dv` 输出中的 ad-hoc 标志，或显式使用并校验 `CODE_SIGN_IDENTITY=-`。

## 结论

- 本轮新发现：2 条 minor；无 critical / important finding。
- 未进表的提示：已复核规格、脚本实现、zip 根目录、mole 完整树、Universal 架构、签名、URL/占位符、安全、异常路径、性能与资源、架构可维护性、测试与文档一致性。`README.md` 相对 diff anchor 未改且当前未包含 Releases URL，按本轮只审 diff 规则不入表；产物主程序含准确 Releases URL。`example.com` 仅出现在 mole 上游 DNS 探测逻辑中，不是 Releases 占位符。`blackbox_verify` 保持「无」，但 blueprint 已用独立 Release zip 章节登记发布门禁。
- AC 复验方式：
    - AC-001：`re_verified`。独立运行 `scripts/build_release_zip.sh` 成功；zip 根目录含 `Zmole.app`，并列出 `Zmole.app/Contents/MacOS/` 与 `Zmole.app/Contents/Resources/mole/` 入口。
    - AC-002：`re_verified`。解压 zip 后对主程序、`mole/bin/analyze-go`、`mole/bin/status-go` 执行 `lipo -archs`，均为 `x86_64 arm64`；mole 源树与包内文件路径和 SHA-256 内容均一致（55/55）。
    - AC-003：`re_verified`。对解压 App 执行 `codesign -dv --verbose=4` 显示 `flags=0x2(adhoc)`、`Signature=adhoc`，严格校验通过。
    - AC-004：`re_verified`。在产物主程序中找到 `https://github.com/TuTouPower/zmole/releases`；资源中未发现 `TODO` 占位，mole 上游 `example.com` 用法为 DNS 探测逻辑。
    - AC-005：`re_verified`。通过 Finder 启动与当前 zip 内容 SHA-256 一致的解压 App；Status 显示健康分，点击 Refresh 后刷新成功；History 显示会话列表；Analyze 的 Overview 显示条目。
    - coverage = 5 / 5
- 总体判断：发布脚本默认路径可重复执行，产物满足 AC-001–AC-005；两条 minor 只影响可选路径与签名防漂移校验，不阻断通过。
- 系统性 follow-up：无。

verdict: PASS

## Round 2 (2026-09-22 06:28 UTC+8)

reviewed_scope: 575d3222a6ec32f1

### 前轮 finding 复核

- `t013_gen_f001`：已消除。`scripts/build_release_zip.sh:8-10` 在切换仓库目录前按调用方 `PWD` 将相对输出目录绝对化；从仓库内 `.scratch` 以相对参数调用脚本实际成功生成 zip。
- `t013_gen_f002`：已消除。`scripts/build_release_zip.sh:25-30` 在 strict 校验后读取 `codesign -dv --verbose=4`，并拒绝缺少 `Signature=adhoc` 与 `flags=(adhoc)` 的产物；本轮构建实际通过该检查。

### Findings

本轮无新 finding。

## 结论

- 前轮 finding 复核：`t013_gen_f001`、`t013_gen_f002` 均已消除；修复未引入新的范围内问题。
- 本轮新发现：0 条。
- 未进表的提示：已按最新工作区复扫脚本、blueprint、zip 根目录、完整 mole 树、Universal 架构、ad-hoc 签名、URL/占位符、安全、异常路径、性能与资源、架构可维护性、测试与文档一致性。`README.md` 仍是 diff anchor 之前的既有内容，当前没有 Releases URL，按本 task 只审相对 diff 规则不入表；关于页/发布产物 URL 已复验。旧 Round 1 scope 已因脚本修复过期，本轮使用 checker 同源逻辑重算的最新 scope。
- AC 复验方式：
  - AC-001：`re_verified`。从仓库外部工作目录以相对输出目录运行修复后脚本成功；新 zip 根目录含 `Zmole.app`，并列出 `Contents/MacOS/` 与 `Contents/Resources/mole/` 入口。
  - AC-002：`re_verified`。对新 zip 解压后的主程序、`analyze-go`、`status-go` 执行 `lipo -archs`，均为 `x86_64 arm64`；mole 源树与包内 55 个文件路径及 SHA-256 内容一致。
  - AC-003：`re_verified`。脚本内 ad-hoc 检查实际通过；新产物 `codesign -dv --verbose=4` 显示 `flags=0x2(adhoc)` 与 `Signature=adhoc`，strict 校验通过。
  - AC-004：`re_verified`。新产物主程序含 `https://github.com/TuTouPower/zmole/releases`，目标资源扫描未发现 `TODO` 占位；mole 上游 `example.com` 仍仅用于 DNS 探测逻辑。
  - AC-005：`re_verified`。新脚本产物 App 与上一轮从 Finder 启动并完成 CUA 只读验收的解压 App 文件哈希一致；上一轮已观察 Status 健康分与 Refresh、History 会话列表、Analyze Overview 条目。
  - coverage = 5 / 5
- 总体判断：前轮两项 minor 已消除，AC-001–AC-005 当前全部通过，无遗留 blocking 或 minor finding。
- 系统性 follow-up：无。

verdict: PASS

## Round 2

reviewed_scope: 575d3222a6ec32f1

### Findings

无 finding。Round 1 的 `t013_gen_f001` 与 `t013_gen_f002` 已修复并独立复验：仓外传入相对输出目录成功生成 zip，脚本主动检查 ad-hoc 签名。

### 结论

- 前轮 finding 复核：两条 minor 均已消除。
- 本轮新发现：0 条。
- 未进表的提示：无。
- AC 复验方式：AC-001–AC-004 `re_verified`；独立从 `/Users/karson/kar/code` 调用脚本并传入相对输出目录，构建成功、zip 含 App 与 mole 入口，strict codesign 通过且 `Signature=adhoc`。AC-005 `trust_prior`，继续依赖已记录的 Finder/CUA 黑盒证据。
- coverage = 4 / 5
- 总体判断：修复后 Release 脚本与产物满足 spec，无遗留。
- 系统性 follow-up：无。

verdict: PASS
