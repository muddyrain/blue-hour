# 分级开发、冻结复用与阶段计时

这是DEV-PERF-02的公开适配规范。入口为[AGENTS](../../AGENTS.md)，新任务复制[模板](codex-task-template.md)。先读[公开状态](../plan.md)现行区，按任务查[功能导航](../features/README.md)和[架构](../architecture.md)相关段落；历史和失败只按影响定位。开发规范落地不代表测得提速，也不改变[已知缺陷](../KNOWN_LIMITATIONS.md)。

## 风险由实际diff决定

| 档位 | 最低验收 |
| --- | --- |
| DOCS/LOW_RISK | 文档/非运行工具：来源、隐私、链接、格式、文件差异和脚本自身隔离测试；公开Git工作核父链、全部可达对象和精确清单。无运行输入变化不重导出或录像。 |
| GAMEPLAY/MEDIUM_RISK | 局部UI/动画/行为且不影响游戏持久化因果：定向回归、相关完整检查；冻结后对应Windows包及真实原生窗口/视觉验收。 |
| PERSISTENCE/HIGH_RISK | 游戏存档字段/协议、冻结结果、快照、死亡、饥饿、事务、READY、迁移、身份代次、JSON哈希或恢复：执行下列安全性质及最终受验包。 |

一旦实际变更涉及游戏持久化、冻结结果或战斗因果对存档的影响，自动升级HIGH；不能只看任务标题或有没有新增字段。计时工具的隔离JSON不是游戏存档。影响未排除时按HIGH处理。

HIGH覆盖受影响的旧格式/严格负例、指纹与规范化往返、跨PID、唯一结算、READY/ACK、死亡及后续营地编辑优先、锁与多写者、真实强杀、原主备字节保护和相同最终包的恢复链。逐项列案例；不适用项须给影响证据，不默认跳过。本公共快照的check只是[可复测子集](../VALIDATION.md)，未提供的历史/强杀矩阵不能被当作通过；需要这些证据但不能完成时保留门禁并报告缺口。

## 执行顺序

1. **驱动预检**：确认入口/参数、依赖及精确版本、全新输出及父目录、隔离APPDATA/profile、稳定成员ID、状态/按钮可见启用/焦点、PID/窗口和等待屏障字段/超时上限。先做短冒烟，预检失败先修编排，保留失败，不盲开长链。
2. **实施与定向**：改动对应的最小因果案例先运行。SCRIPT ERROR即使退出0也不是通过；原因未定写UNKNOWN。普通回归默认不录像，资料只写本地隔离区。
3. **最终冻结**：列源/资源/配置、未跟踪运行输入、驱动与夹具、引擎、参数和包身份。输入继续变化时解释哪些检查失效并重新冻结。
4. **集中验收**：按风险满足必要完整检查及最终包。保留失败与修正链；只重复失效范围，不把进程数量当覆盖率，也不缩减HIGH安全性质。
5. **交接**：更新相关说明和公开plan，提供精确文件差异、测试层级、失败/限制及本地提交。推送、PR、合并、Release分别依当次授权，不让用户在内部验证阶段手动中转。

当前公开tools/godot.py仅支持check/run，没有export子命令；游戏check含导入、主场景和组件子集。需要导出时先核实际编辑器/构建入口及模板，避免无依据地重复同一完整检查；不新增绕过安全检查的参数。LOW计时工具可只运行自己的19项测试，不借此宣称新游戏验收。

## 旧结果安全复用

每个拟复用结果保留原日志/结果SHA、原日期/条件/层级、范围与新旧身份逐项比较。路径、文件名、大小、Git状态相同都不足以证明身份。

| 身份 | 必需依据 |
| --- | --- |
| 源/资源/配置 | 内容SHA清单，或Git tree加受审未跟踪运行输入清单；仅文档变动时用逐文件清单证明运行闭包未变。 |
| 引擎/构建 | Godot精确版本和可执行SHA、渲染器、导出设置/模板身份、平台及方式。 |
| 驱动/夹具 | 控制器、外置脚本、夹具、配置SHA，以及其稳定ID/按钮/状态/屏障语义。 |
| 参数/profile | 启动参数、schema/BUILD/协议、种子、场景、隔离边界和原始输入/副本SHA。 |
| 包内通过 | 同一EXE/PCK SHA及影响加载的外部数据；源码检查不能冒称包内通过。 |

缺必需值写UNKNOWN并重验所需范围。任一相关输入变化，列“失效检查→依赖变化→重验范围”；证实无影响的另列依据。跨存档协议、引擎或导出包不复用为新版本通过，原结果仍是历史对照。引用复用不计作本轮新增断言/进程；无界面、原生窗口、包内与OS物理输入层级不互相升级。

例：只改报告且相关运行清单、引擎、驱动、条件和原包SHA全部相同，可注明日期引用旧包结果；若只改外置控制器，即使PCK没变，该驱动相关结果也失效。不要把冻结清单写入或改动游戏兼容协议。

## 计时工具

tools/task_timing.py为Python 3.10+标准库工具，无联网或模型设置操作。输出只允许项目.local/task-timing下的明确JSON，拒绝越界、链接/重解析点/硬链接、非工具文件、坏时间与重复事件。一个文件一个task，新run选新路径，不覆盖既有终结事件；失败重试新增attempt，非pass必须有原因，未诊断写UNKNOWN。

```powershell
python tools/task_timing.py start --task EXAMPLE-01 --phase inspection --out .local/task-timing/example-01.json
python tools/task_timing.py stop --task EXAMPLE-01 --phase inspection --status pass --out .local/task-timing/example-01.json
python tools/task_timing.py report --out .local/task-timing/example-01.json
python -m unittest discover -s tests/tools -p test_task_timing.py -v
```

示例必须使用尚不存在的独立run路径。阶段有inspection、implementation、driver_precheck、targeted_test、final_check、export_windows、media、handoff；同阶段只一个running，不同阶段可并行。UTC起止差是显式包住的可见区间，可能包含等待/阅读/其它活动，不能当CPU或模型思考时间。闭合区间取并集，不把重叠相加当总墙钟；已记录跨度内的间隙仅报告未覆盖秒数，其归因UNKNOWN。开放事件及完整任务边界UNKNOWN，完整任务墙钟、隐藏推理、token、重连归因不可由相减推测。未开始计时前不回填，不宣称提速百分比。

时钟回退拒绝结束并保留UNKNOWN；busy锁稍后重试，不自动删除未知锁。每记录上限1MiB，满后保护原件另开run；本机文件系统不支持排他创建/原子替换时明确失败。原因只写短说明，勿填私人路径、邮件或凭据。测试中的路径/邮件/令牌样式是明确合成的拒绝测试字面值，不是真实资料；测试只在.local/task-timing-tests随机临时假项目内操作，可用BH_TIMING_TEST_TMP指定本项目.local里的新scratch。

## 本地产物、隐私与交接

测试/导出/媒体前后只读盘点.local容量、增量和最大任务目录，先定预算。新任务分scratch/report/evidence/deliverables/protected-profile；失败原件、唯一可用包、历史媒体、存档/备份均保留，不按年龄删除或覆盖。普通回归不录制，只保留明确最终媒体与包；同盘副本不称异盘灾备。

WATCH_OPEN、OS-NOT-VERIFIED和NO-GO-PRODUCTION不因优化关闭。RECORD_READBACK:RECORD_HASH未修，正式生存BLOCKED，旧档不放宽校验，默认入口不切换。所有项目暂行参数仍PROJECT_TEMP，不冒充经典Deadly Days实测。

公开交接提交脱敏文档和工具，原始profile/日志/计时样本及研究不进Git。若当次任务另要求私有ChatGPT审阅包，使用该环境已有打包流程，核CRC/SHA和独立解压；纯工具无媒体标NOT_APPLICABLE，不伪造。本公共快照不提供内部打包器、研究或私有验证器，不引用不存在的内部文件。模型级别对照和其它玩法/协议变更须独立范围，不更改Codex设置。
