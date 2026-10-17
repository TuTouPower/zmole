# 保护规则与白名单（whitelist）

- 来源 task：t007、t024（白名单部分）
- 生效范围：clean 白名单、optimize 白名单编辑
- 最后更新：2026-10-17

## 行为契约

- clean 白名单文件为 `~/.config/mole/whitelist`（路径模式）；optimize 白名单为 `~/.config/mole/whitelist_optimize`（任务 id 行）。两份都可在设置页进入编辑。
- 编辑器列出非注释模式行；添加/删除后保存，文件内容与编辑结果一致；注释行保留、不被当成任务 id。
- optimize 白名单只接受合法任务 id（`[A-Za-z0-9_.-]+`）；非法行给出本地化错误。
- 保存 clean 白名单成功后使现有清理预览失效（preview generation 递增）。
- 本功能不 spawn mole 进程。
- 保存走共享写入租约（`.protectionRules`），争用时给出可恢复忙碌提示；保存失败保留编辑内容并显示原因（中文兜底文案或本地化 key）。
- 从清理页「保护」按钮加入白名单：重复/未加载/写盘失败时在清理页给出可见反馈，不静默假装成功。
- 文件不是有效 UTF-8 时显示本地化错误键而不是原始中文描述。

## 验证

- `tests/unit/ZmoleTests.swift`（whitelist store 往返、编辑器）
- `tests/unit/CleanPageTests.swift`（保护路径使预览失效）
