# 公开开发状态

[M6-ROGUE-01](design/m6-rogue-01.md)从已审75abe0b继续；#6/#5未合并时，独立分支以codex/m6-playable-01为PR base。正常试玩接入每日三个稳定候选、补给/装备/合资格救援，以及长街/三岔/环院模块街区。实际收益、空间、出击、冻结及恢复绑定一份描述；2/3/4人HUD改为紧凑单排。

风险PERSISTENCE/HIGH_RISK，按实际变化验新规则data_version2、新世界version3、生成地图身份/负例/往返/跨PID与旧完成/旧途中边界，保留原精确编码、认证、死亡/饥饿及唯一结算。当前Mac即可，后台采集，不运行原作。正式生产门禁仍BLOCKED，未合并/Release；实际结果及未验项见[验证边界](VALIDATION.md#m6-rogue-01mac每日行动与街区)。以下阶段按各自历史范围保留。

[M6-PLAYABLE-01](design/m6-playable-01.md)从已审接触候选427cbb8继续，正常启动进入独立、稳定的开发试玩；营地准备、任务选择、真实搜集/救援、巴士集合、结果预览/确认和再次行动使用既有业务链。新分支依赖未合并PR #5，以codex/m5-contact-01为PR base，不向前置分支追加代码。

本轮仅Mac开发验收，保留ANIM-02、V1和接触修复。风险按实际影响为GAMEPLAY/MEDIUM_RISK，另验保存路由/旧档保护、跨PID继续、保存失败与唯一确认；编码/事务/恢复/死亡身份/唯一结算合同没有变更，不重复无关强杀、锁竞争、历史档矩阵。具体结果见[验证边界](VALIDATION.md#m6-playable-01mac完整试玩)。执行规范在同一PR按最新用户要求简化。

**正式生存发布门禁仍BLOCKED / NO-GO-PRODUCTION。** 开发试玩不是正式发行；Windows、物理键鼠、人工显示观感及未提供的内部历史原件不推定通过。没有Release，不新增三天通关、地图生成或新死亡规则。

以下各阶段按历史范围保留，不把旧包结果计作M6候选通过。

## P0-RECORD-HASH-02：HASH_COMPONENT_PASS / REVIEW_REQUIRED

从公共main 21c5c59d43259070ae743ff695d505c2c89c71ee 在独立任务分支接入 BH_EXACT_JSON_V1；历史业务指纹、binding v1、旧有效记录字节和链不变。未知版本/坏摘要严格拒绝，没有容差或双算法兜底。具体合同见[精确收据设计](design/p0-record-hash-02.md)。旧内部工作区和所有原件保持。

最终冻结后公开15组、编码80项、工具25测通过；同一最终Windows EXE/PCK 62进程、877项断言、14次真实强杀通过，含实际锁/并发、完整代次ACK/结果/死亡补位营地优先、合成旧格式与混合链、新旧包降级拒绝及独立桌面原生渲染。详见[本轮验证](VALIDATION.md#windows精确收据p0-record-hash-02)。此前驱动失败均保留，不复用为最终包通过数。

本轮仅修传输边界并补公开合成驱动，未切普通默认或改玩法/素材/导航。真实内部历史原件NOT_PROVIDED；物理OS输入、显示流畅性、跨机器/系统、任意断电NOT_VERIFIED。原WATCH/接触穿叠及NO-GO-PRODUCTION保持，正式生存BLOCKED。按授权提交并推任务分支、创建Draft PR；下一项仅主线审阅决定是否合并，不自动Release或继续玩法。

## WIN-PUBLIC-SYNC-04：Windows软件层复验完成，保持Draft

2026-11-03从公共e4b65ac62bfcf9792c66cbcdfad007e63c5606a9独立干净克隆，禁用局部自动换行转换；501文件逐字节核对后重新导入。固定Godot与Windows模板，Python3.13.5/Pillow12.3.0；公开14组为13 PASS及1 EXPECTED_KNOWN_FAILURE，未改哈希重现器或检查语义。

同一Windows x86_64 EXE/PCK的动作检查29项及菜单检查74项通过；固定引擎加载同PCK的八向/六步态/事件姿态、1280×720与1024×576画面及11项viewport输入检查通过。实际EXE另留41.8秒连续受控录像，MovieWriter输出1280×720/30fps，不是显示器FPS。原生OS输入尝试受焦点干扰未完成；按用户要求停止Computer Use，后续自动输入与渲染在不切换的独立Windows桌面执行。相关失败与修正详见[验证边界](VALIDATION.md#windows复验win-public-sync-04)，原始日志和媒体仅私有保留。

没有游戏代码或资源修复；本次仅同步验证文档，默认入口、存档、数值、导航和碰撞保持。软件表现验证通过不等于正式生存可发布；物理键鼠、显示流畅性、自然任务全程及P0完整矩阵未签核。PR保持Draft，等待审阅后另行决定合并；下一步是人工物理输入签核或独立P0/接触移动任务，不在此轮推进。

## 开发工具：DEV-PERF-02

公开快照新增标准库阶段计时器、19项隔离单测、风险分级/预检/冻结复用规范及任务模板。这里只描述可用能力，不含内部阶段账本、实际耗时或研究证据，也不代表已测出提速比例。本轮仅投影ANIM-02＋V1表现和相关检查/文档，五篇Feature入口、14张图及默认入口保留；RECORD_READBACK:RECORD_HASH未修，正式生存BLOCKED，不创建Release。
