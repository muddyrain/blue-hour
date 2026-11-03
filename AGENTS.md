# Blue Hour 公开协作约定

先读README与docs/plan现行状态，按实际diff查相关功能；修改运行实现时读docs/architecture相关边界；先核实Git状态，保留无关修改。使用相关skills；GitNexus不可用时明确回退原生Git。保持固定Godot版本、类型化GDScript和显式依赖。

不得用真实玩家进度做测试。公开复测入口是python tools/godot.py check，输出仅在忽略的本地目录；原作安装、研究媒体与私人资料不在本仓库范围。交互与导出另需实际验证，不能用内部历史结果代替新候选结果。

当前精确收据传输为待审候选，正式生存门禁BLOCKED。不要放宽旧档校验、凭空重建死亡或把检查退出0说成可可靠恢复。人数及新增数值为PROJECT_TEMP，不是原作精确事实。

公共提交从当前公共main继续，只投影明确审查的文件；不要引入内部研发提交祖先。发布前审计完整可达对象、素材来源、隐私和克隆构建。推送/PR/合并/Release分别按当次授权；不重写历史，不强推，不新增未经授权的许可。

## 分级执行与可观察计时

- 开工按实际diff标DOCS/LOW_RISK、GAMEPLAY/MEDIUM_RISK或PERSISTENCE/HIGH_RISK；游戏持久化、冻结结果、死亡/身份或战斗存档因果自动HIGH，不按标题豁免。
- LOW检查来源/隐私/链接/差异与工具隔离测试；MEDIUM验定向、相关完整检查、冻结后Windows包/原生视觉；HIGH执行[风险矩阵](docs/development/codex-execution-efficiency.md)的旧档/负例/往返/跨PID/唯一结算/READY-ACK/死亡营地优先/锁多写者/强杀/主备及最终包。公开check子集不替代缺失安全矩阵。
- 驱动预检→实施与定向→冻结→必要最终验收→文档交接。先核入口/参数/目录、稳定ID、按钮焦点/状态、PID/屏障和超时；失败先修编排，原件保留。
- 复用前逐项核相关源/资源、未跟踪输入、精确引擎/渲染导出、驱动夹具、参数/profile及EXE/PCK SHA；UNKNOWN不推定相同，跨协议/引擎/包不套旧通过数。范围与例子见规范。
- 用[任务模板](docs/development/codex-task-template.md)开工；task_timing仅记录显式UTC阶段与失败重试，重叠取并集，完整任务/隐藏推理/token/重连归因UNKNOWN。不改变模型设置，不宣称未经对照的提速。
- .local只存隔离产物；前后盘点容量/预算/最大目录，保留失败/唯一包/存档/备份，不自动回收历史。原始记录和私有审阅ZIP不公开，LOW无新媒体标NOT_APPLICABLE。
