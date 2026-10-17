# 设置（settings）

- 来源 task：t024（设置部分）、t003（语言/外观）
- 生效范围：设置页、登录项、CLI 信息行
- 最后更新：2026-10-17

## 行为契约

- 界面语言（跟随系统/简中/繁中/英文）与外观（跟随系统/浅色/深色）经 `@AppStorage` 持久化并在下次启动与当次即时生效（含 `environment(\.locale)` 覆盖）。
- 登录项经 `SMAppService` 注册/取消：注册失败时开关保持关闭并显示原因；注册成功但系统未就绪显示等待文案；取消失败显示原因、开关状态保持与事实一致（不静默吞错）。
- 设置页包含：两份白名单编辑器入口（clean/optimize）、项目扫描目录编辑器入口、登录项、CLI 信息行、关于入口。
- CLI 行显示捆绑 `SOURCE_VERSION` 的 tag 与 bundle 内路径；指示符按可执行文件存在性区分「已连接/未找到」；不探测系统 `mo`。
- 不做菜单栏常驻；不提供「移除前检查」「包含浏览器缓存」开关。
- 关于页显示捆绑 mole 版本（取自 `SOURCE_VERSION`，缺失显示本地化「未找到」）与 GPL-3.0 说明，链接 GitHub Releases。
- 无网络请求、无遥测。

## 验证

- `tests/unit/SettingsHistoryTests.swift`、`tests/unit/ZmoleTests.swift`
- `tests/unit/NavigationTests.swift`（设置页入口）
