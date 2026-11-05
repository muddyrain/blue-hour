# M8-BUILD-01 WIN-R1：局内道具与基础支援

本轮为开发候选，正式生存门禁保持BLOCKED。正常新旅程默认构筑模式；保留四次准备、终局、两枪、个人Trait、原口粮和永久死亡。已合并#11→#12后从main d209d5ef430f3edce2f4393b49f103cbb16c8cd0开发。接口和文件所有权见[共享合同](m8-build-01-interfaces.md)。

## 玩家规则与证据层级

OFFICIAL_HISTORICAL：经典Deadly Days（740080）的[2019-05 Update0.50与2019-03开发日志](https://store.steampowered.com/news/posts/?appids=740080&enddate=1568884297&feed=steam_community_announcements)支持任务资源方向，以及Trait、被动道具、基础冷却能力与按日充能Special Power分层。旧键位不作为现代合同。[2024-10-28经典1.7公告](https://steamcommunity.com/app/740080/allnews/)的Hoarder条目支持道具槽与按相对生命缺损选择治疗目标；排除同页Roadtrip新闻。[2019-11开发/发行方答复](https://steamcommunity.com/app/740080/discussions/2/1639801448914199658/)仅支持任务资源方向及仓库基础道具的历史线索，玩家数量表不是本机实测。

PROJECT_ADAPTATION：两个免费小队被动槽、六件池、每次装备主cash站点最多两件未拥有道具、首行动保证装备候选、营地自由换装、全场治疗、最近合法呼叫者归属和Q/E输入。取得须真实完成回收，确认归航后入库，下次行动生效。未装备库存不生效，途中不可换装。集齐六件后只保留原枪械/钱粮奖励。没有阶段三选一、永久强化、额外货币、Special Power或每日支援次数。

UNKNOWN：原作精确掉率、道具槽价/解锁、所有拾取细节及技能数值。本轮未安装/启动原作，未读原作档或研究原件，未新增外部美术/音频。

## PROJECT_TEMP V1参数

| 被动 | ID | 效果 |
| --- | --- | --- |
| 高压弹头 | pressure_rounds_v1 | 枪械直伤×1.20 |
| 快装组件 | quick_loader_v1 | 换弹时长×0.75 |
| 轻便行装 | light_boots_v1 | 移速×1.15 |
| 野外工具 | field_tools_v1 | 搜刮/户外回收耗时×0.75 |
| 扩散装药 | wide_blast_v1 | 基础空袭半径×1.30 |
| 医疗补包 | medical_pack_v1 | 治疗上限×1.50 |

原武器等级、品质、词缀与个人Trait先计算，再应用冻结槽位一次；不更改攻速、射程、最大HP、救援接纳、巴士或首领预警。定义集中在BuildItems；治疗40HP/30秒（补包60HP），空袭320px/90px/72伤害/20秒（装药117px），集中在BasicSupport.POLICY。

Q或按钮治疗当前存活、非满血且生命比例最低成员，同值稳定member_id。E进入空袭瞄准，左键确认，右键/Esc取消；Esc先取消瞄准。有效地面、合法呼叫者范围和墙体视线均沿原空间数据验证。空地可施放，无友伤，枪弹/换弹/移动指令不消费。UI接收输入后不会传给战场。

## 数据与唯一owner

新journey.build version1记录owned、两个slots、获取sources与累计实际healing；槽位编辑走原CampEdit/ProductionProgress，保存未确认时保留旧配置。旧旅程无build继续原模式。新generated7、rules8、world10明确绑定道具定义、支援策略、出发owned和slots、drop_context/drops；旧generated6/rules7/world9及更早分支仍按原生成器认证。不会由当前营地倒推历史掉落。

BuildState只推演库存结果，原FrozenSettlement和确认ACK负责入库。来源绑定run/seed/day/action/site及出发owned，规范事务序号和来源顺序严格检查。站点完成事实供携带/恢复/归航共同读取，没有第二个库存文件或奖励结算器。

BuildAuthority生成值快照提案；RunTransaction验证原前态、请求和整个后态，在原journal追加带support_proposal的SUSPEND_READY并确认claim后，Expedition才替换可见运行状态。失败保持原HP、冷却和批量敌人状态，暂停保留同一请求供重试；未知ACK沿同一已发布候选继续。全过程一个写者。

新生命因果为当前HP+累计实际受伤=出发HP+已接受实际治疗；治疗记录绑定请求、成员、精确模拟时间和实际量，溢出不入账。死亡仍由PersistedDamageGate/原死亡事务确认，HP0不会治疗或复活。服务累计受伤的上界纳入原结算确认的治疗总量，不减伤害账。

空袭致命输入使用明确ability来源、airstrike_v1、request_id、实际呼叫者和目标，无假枪械ID或子弹。先核目标/账本容量/完整后态，再原子发布整批；原service/XP/生还归航owner结算每击败10XP。首领凭证引用首领自身事件，死亡清pending/handling，非致命则调用原BossBehavior更新真实阈值，保留R1重试与严格来源校验。

世界快照保存支援精确剩余冷却和完整接受记录。每次行动初始就绪，暂停、到达、离场、冻结和结束停表；活跃/集合以权威delta推进。冷却认证使用精确接受模拟时间，不以毫秒取整推算剩余量。原精确编码、死亡、换弹、首领与一次归航链保留。

## 公开复测

`python tools/godot.py check --godot <固定引擎>`；Windows定向闭环用`python tools/build_flow.py --godot <固定引擎> --output .local/build-proof --native`。加`--movie`需ffmpeg，采集经声明接缝的1×必要片段，使用独立Windows桌面，不切用户桌面。所有自动验证使用新隔离profile；检查结果不等于人工手感、物理输入或显示FPS签核。
