# 约定（项目级）

模板流程的编号与 Markdown 格式见 `.repo_template/docs/usage.md`「命名与格式」。本文只写本项目的语言、框架与 schema 落点例外。

## 语言与框架

- **语言**：Swift 5.9+（随 Xcode 工具链）
- **UI**：SwiftUI，最低部署目标 **macOS 13+**，Universal
- **本地化**：String Catalog；`zh-Hans` / `zh-Hant` / `en`；默认跟随系统，设置可覆盖
- **并发**：优先 `async/await`；Bridge 内 `Process` I/O 勿堵主线程
- **目录**（Xcode 工程落地后）：
    - `src/zmole/App/` — 入口与 App 级场景
    - `src/zmole/Features/<Feature>/` — 功能页
    - `src/zmole/MoleBridge/` — CLI 桥接
    - `src/zmole/Models/` — 共享模型
    - `tests/unit/` — 纯逻辑单测（Bridge 解析、参数拼装等）
    - `tests/integration/` — 对捆绑 mole 或假二进制的集成
- **工程文件**：根目录 `project.yml`，XcodeGen 生成 `Zmole.xcodeproj`；禁止手写损坏的 pbxproj
- **捆绑 mole**：构建时放入 Resources；运行时只 spawn 该绝对路径
- **禁止**：Feature / View 里直接 `Process`；解析 TUI；代发按键；把 CLI 装进 PATH；调用捆绑 mole 的 `update`/`remove`
- **文件名**：Swift 类型文件用 UpperCamelCase（生态惯例，优先于全局 snake_case 目录规则中的「普通文件」条款）；目录名仍用 snake_case 或与 Feature 名一致的 UpperCamelCase 模块文件夹

## schema 类型落点

按消费方决定落点，`schemas/` 只放跨服务契约。

|类型|例子|落点|
|---|---|---|
|跨服务接口契约|OpenAPI、gRPC `.proto`、GraphQL `.graphql`、AsyncAPI|`schemas/`，按协议分子目录；单一协议直接扁平|
|代码内数据契约|Swift `Codable` / 结构体|跟模块：`src/zmole/Models/` 或 Feature 内|
|CLI JSON 契约|`mo status --json` 等响应形状|`schemas/mole_cli/` 放 JSON Schema 或示例 JSON（若开始做严格解码）；解码类型仍在 Models|
|配置 schema|App 设置、env|`config/` 或跟消费方|
|文档/元数据 schema|front matter、YAML metadata 校验|`docs/schemas/`，或跟文档源|

原则：

- 跨服务契约会触发上下游同步，独立根目录便于发现和工具扫描。
- 代码内契约不外露，跟源码同源，避免双份维护。
- mole CLI 的 JSON 若无稳定公开 schema，先用 fixture + 宽松解码，契约稳定后再写入 `schemas/mole_cli/`。
