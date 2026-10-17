# 安装包（installers）

- 来源 task：t022、t023、t030
- 生效范围：安装包页、非交互接口消费
- 最后更新：2026-10-17

## 行为契约

- 列出走捆绑 installer 非交互接口 `installer --list-json`（绝对路径、字节大小、来源、身份）；不进入全屏选择界面、不代按键。
- 扫描规则由捆绑脚本负责（目录、深度、ZIP 判断）；不含安装包内容的普通 zip 不出现；dmg 出现。
- 删除走 `installer --remove <path> --size <n> --identity <id>`；只接受调用方会话名单里的路径，GUI 侧先做防御性校验（绝对路径、size>0、identity 非空）；CLI 侧直接核对目标自身（仍在扫描根内、该深度、候选扩展名、大小与 identity 未变）；删除不重新遍历扫描根（同一名单多次删除只遍历一次）。
- 删除显式走废纸篓（`MOLE_DELETE_MODE=trash`）；移动失败保留原文件，不退回永久删除；界面写明移入废纸篓。
- 未列出或未确认时删除调用次数为 0；取消确认后不删除，再次删除必须重新确认同一次列出结果；部分路径被接口拒绝时页面保留这些路径与失败原因。
- 忙碌（通道争用）中止批次、保留剩余选中并显示可恢复提示；移除进行中提供「当前项后停止」取消按钮。
- JSON 列表解析容错：单行字段缺失跳过该行（source/identity 缺省），全坏抛解析错误而不是伪空列表；解析错误经本地化 key 渲染。
- 无完全磁盘访问权限时不发起名单扫描（会遍历 Desktop/Documents/Downloads）：页面显示授权横幅（打开系统设置 / 重新检测），扫描按钮不可用；授权后回到页面自动扫描。

## 验证

- `tests/unit/InstallersPageTests.swift`
- `tests/integration/installer_interface_test.sh`（真实 installer.sh + 隔离 Trash/扫描根）
