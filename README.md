# zmole

把开源 CLI [mole](https://github.com/tw93/mole) 包装成 macOS 窗口应用。清理、卸载、优化等仍由捆绑的 mole 执行；本仓做界面与确认。

许可：GPL-3.0。与商业产品 [Mole for Mac](https://mole.fit/) 无关，也不使用其商标与 logo。

从仓库模板复制而来。工具链在 `.repo_template/`。实现计划：[`docs/plan.md`](docs/plan.md)。

## 运行时

- 不要求用户先 `brew install mole`
- App 内捆绑钉死版本的 mole，不把 `mo`/`zmo` 装进 PATH
- 系统语言为简体、繁体或英文时跟随；可在设置里覆盖

## 从 GitHub 下载后打不开

未公证。浏览器下载会带隔离属性。按顺序试：

1. 右键 `Zmole.app` → 打开 → 仍要打开
2. 系统设置 → 隐私与安全性 → 仍要打开
3. 仍失败时在终端执行（把路径换成实际位置）：

```bash
xattr -cr /Applications/Zmole.app
```

## 入口

- Agent 规则：[`AGENTS.md`](AGENTS.md)
- 模板用法：[`.repo_template/docs/usage.md`](.repo_template/docs/usage.md)
- 约定 / 测试 / 架构：[`docs/blueprint/`](docs/blueprint/)

## 开发

需要完整 Xcode（不只 Command Line Tools）：

```bash
sudo xcode-select -s /Applications/Xcode.app
# 工程由 XcodeGen 生成（落地后）：
# xcodegen
# xcodebuild -scheme Zmole -configuration Debug build
```

上游对照克隆（只读，不打进包）：`~/kar/github_repo/mole`
