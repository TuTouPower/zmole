# p013 概览「存储估算」长期无结果：触发窗口错过即永不重试，且 /Users 扫描超时归零

- 现象：Release 版打开概览后长时间（>2 分钟）五段估算全部显示「—」并标「估算不完整」；缓存文件停留在旧 schema 不再更新。
- 影响：概览核心信息（存储估算）不可用；概览四卡中存储卡、健康卡（可回收/状态相关）无法呈现真实数据。已确认同类位点：无其它调用方复用同一「窗口式触发 + 完整才采纳」组合（磁盘页已与 analyze 解耦；卸载/安装包名单走流式与预跑，各自有独立超时与重试）。
- 根因：
    - A 触发缺失：`OverviewView.task` 只在视图出现后约 13 秒内等一次 `usedBytes`（status 快照），之后调用一次 `refreshEstimateIfNeeded`；`usedBytes` 为 nil 时 `computeEstimate` 静默跳过，且此后没有任何「status 到达」触发（`onChange` 只监听 `estimateInvalidated`）。实测三次全新启动 45–140 秒窗口内应用从未 spawn `analyze --json`。本机启动期预跑扫描压低 status 采样（捆绑 `status-go --watch` 负重时 6 秒仅 2 行），窗口易错过。
    - B 超时归零：即便发起，`analyze --json /Users` 实测 >135 秒（另一次 >900 秒）远超估算通道 120s 超时 → `timedOut` → users 段 nil；当前策略「四路径全齐才落盘、才渲染」（t036 评审 f001 严格化），于是永远只有占位、永不落盘、永不覆盖。另：估算扫描绑定视图 `.task`，切页即被取消，长扫描难以完成。
    - 环境佐证：旧缓存（schema1，00:33）users=734GB 曾算成，说明该段并非恒不可算，当前 I/O 负载与超时组合使其常态失败。
- 测试缺口：现有 Overview 测试全部注入即时返回的假 loader（或立即 nil），从未覆盖「status 迟到导致的触发窗口错过」「视图消失取消扫描」「真实超时路径」「部分段可用时应先展示并可落盘」；`testIncompleteScanIsNeitherPersistedNorRendered` 反而固化了 B 的全有全无策略。应补：可控时钟/loader 的「usedBytes 迟到 → 仍发起并完成」用例、估算任务不随视图取消的用例、部分段展示+落盘且持续重试的用例、超时→该段占位但其余段展示的用例。
- 线索：`.scratch/bug_storage_estimate/repro_notes.md`（含进程采样、命令耗时、缓存实况与代码定位）。
- 处理：未开
