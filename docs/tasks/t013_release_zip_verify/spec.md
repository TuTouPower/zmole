# Task spec

## 背景

t012 只交图标与 README。空壳 App 不能当发布。本 task 在功能齐后打 zip，验收解压后的真实产品。

## 契约区

### 范围

- 可重复脚本：Release 配置构建、ad-hoc 签名、打出含 `Zmole.app` 的 zip
- zip 内完整捆绑 mole 树；`lipo -archs` 主程序与 `analyze-go`/`status-go` 均为 x86_64+arm64
- 关于页 / README 的 Releases 链接为 `https://github.com/TuTouPower/zmole/releases`
- `[deploy]`：解压 zip，从 Finder 打开（本机可先 `xattr -cr`），跑通 status 刷新、history 打开、analyze overview

### 非范围

- Developer ID / 公证 / dmg / Sparkle
- 真机破坏性删除

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：发布脚本产出 zip，列出内容含 `Zmole.app/Contents/MacOS/` 与 `Contents/Resources/mole/` 入口
- [ ] AC-002：对该 `.app` 主可执行文件、`Resources/mole/bin/analyze-go`、`status-go` 执行 `lipo -archs`，均含 `x86_64` 与 `arm64`
- [ ] AC-003：`codesign -dv` 显示 ad-hoc 或等价本地签名（不要求 Developer ID）
- [ ] AC-004：二进制或资源中的 Releases URL 为 `https://github.com/TuTouPower/zmole/releases`，无 `example.com` / `TODO` 占位
- [ ] [deploy] AC-005：解压后从 Finder 启动，status 能刷新出健康分，history 页可打开，analyze overview 有条目

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001–AC-004：脚本
- AC-005：手工 Finder

## 上下文区

- 来源：审阅 P2 发布验收；ADR-003、ADR-005

### 有意不测

- 每台陌生 Mac 的 Gatekeeper 点法：README 已覆盖，本 task 只在开发机解压启动

### 测试策略

- 构建脚本 + lipo/codesign；手工只读三页

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无

### 风险与回退

- 风险：zip 进了 DerivedData 半成品、漏 helper
- 回退：脚本只打包 Release 配置 + AC-001/002

### 依赖与约束

- 依赖 t002–t012（功能与图标齐）

### Finalization 时更新的 blueprint

- `docs/blueprint/testing.md`：若有发布脚本，写入 blackbox 或单独章节说明
