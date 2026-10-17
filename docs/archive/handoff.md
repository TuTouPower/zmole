# 历史交接

由 `repo-hygiene` 从 `docs/handoff.md` 迁入。**只追加**，禁止截断或改写已归档段落。

## 2026-09-21T12:26:08+08:00 init → owner

- 当前焦点：仓库已从 repo_template 初始化；技术栈定为 SwiftUI + MoleBridge；需求后已由 grilling 取代。
- branch：main
- head_commit：d40fd76c2b97b8c5582d810f18cb72eca12b8711
- 已完成：模板复制、软链、hooks、初始 blueprint
- 未完成：当时尚未确认捆绑/分发/功能切分
- 陷阱：当时文档仍写「调本机 mo」，已作废
- 下一步：见现行 `docs/handoff.md`


## 2026-09-21T16:00:00+08:00 grilling → owner

- 当前焦点：已按审阅改 backlog（卸载 `y\n`+path 身份、预览世代、Universal 必交、t013 发布验收、纠正 purge/`--yes`）。可 start t001。
- branch：main
- head_commit：903b633e80bf9ab81a331d073a0b075bc126eec9
- 已完成：grilling 锁定产品；plan / architecture / domain / decisions / README
- 未完成：Xcode 工程、捆绑 mole、各功能页、图标与 zip
- 陷阱：不公证；空 stdin 可能误确认删除；不要 spawn 系统 `mo`；installer 等已 park
- 下一步：同意后提交本批 backlog；环境切 `xcode-select` 到 Xcode.app
