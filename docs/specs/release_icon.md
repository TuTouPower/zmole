# 图标与发布（release_icon）

- 来源 task：t012、t013、t033
- 生效范围：应用图标、Release zip、签名与文档入口
- 最后更新：2026-10-17

## 行为契约

- 图标源为 `assets/` 的矢量 SVG（彩色主版 `app_icon_source.svg` 为唯一构建源；黑白 `app_icon_source_mono.svg` 备用）；`src/zmole/Resources/AppIcon.icns` 由 `scripts/build_app_icon.sh`（经 `scripts/svg_to_png.swift` 渲染透明 PNG + sips + iconutil）生成，改源后重新生成并同 commit 提交。
- icns 含全部尺寸（16–512@2x）；512 角透明、字形不透明（透明背景，不出现白底文档预览）。
- 构建出的 `.app` 使用新图标；侧栏品牌图标优先直读 bundle 内 `AppIcon.icns`，失败回退 `NSApp.applicationIconImage`。
- Release 脚本（`scripts/build_release_zip.sh`）产出 `artifacts/releases/Zmole-<version>.zip`，内容含 `Zmole.app/Contents/MacOS/` 与 `Contents/Resources/mole/`；强制校验 `Zmole Local Signing` 签名（身份由 `scripts/setup_signing_identity.sh` 一次性建入登录钥匙串，代码身份跨重建稳定）；不把 mole 源码或凭据打进 zip。
- 主可执行文件与 `Resources/mole/bin/analyze-go`、`status-go` 均为 arm64 + x86_64（lipo 或等价双切片布局）。
- 二进制/资源中的 Releases URL 为 `https://github.com/TuTouPower/zmole/releases`，无占位符。
- README 同时包含 Gatekeeper「仍要打开」步骤与 `xattr -cr` 备路（加限定语：仅对本项目 App），并注明 macOS 13+ 与捆绑 mole tag；不公证、不上架 App Store。

## 验证

- `tests/unit/AppIconTests.swift`（源文件存在、尺寸集合、透明度、无旧源引用、侧栏引用）
- `scripts/build_release_zip.sh` + 发布验收（lipo/codesign 检查）
