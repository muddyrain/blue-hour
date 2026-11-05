BuildItems与BasicSupport只作纯定义/规划/只读组件；BuildActions显式generated7冻结出发构筑，BuildState推演原营地库存。BuildAuthority生成完整支援前/后态证明，原RunTransaction journal原子持久化后由Expedition应用，FrozenSettlement仍是唯一归航结果owner。旧模式独立认证；详见[构筑合同](design/m8-build-01.md)。

ReceiptJournal的R1缓存仅复用完整原文和相邻原文的纯认证证明；每次仍重读真实文件、检查全链与binding，不缓存当前营地/ACK权威。FreezeProfile仅为默认关闭的聚合计时；没有新保存格式或异步owner。

NeighborhoodActions/Layout/Art提供V3尺寸、主题和每类门尺度；实体院墙与所有空间消费者读取同一StreetLayout。DailyActions保留V1/V2认证，新增规则4/世界5，不另造保存或奖励owner。见[尺度与拓扑](design/m6-world-02.md)。

WorldActions/WorldLayout/WorldSites提供V2有限街区、站点预算与事实校验；DailyActions按版本保留V1解释。BuildingLibrary拥有素材和门锚点，BusJourney只读已登记行动/冻结结果并推进表现。原数据owner继续唯一保存；详见[街区合同](design/m6-world-01.md)。

# 架构与所有权

CampaignRules只提供纯阶段/显示，CampaignActions在原V5之上冻结V6阶段及导航验证首领定义。BossBehavior只产生稳定请求，BossWarning只读绘图；EncounterRuntime在Expedition内调用原攻击、伤害、刷怪与击败/XP owner。FrozenSettlement在原结果内推演journey.campaign，ProductionProgress确认提交后才成为持久结果；世界9保存同一首领和请求事实，没有另一个存档或归航结算器。旧111无campaign字段时保持原模式，历史指纹分支保留。见[短局合同](design/m8-run-01.md)。

WeaponActions只在原TaskActions描述上冻结V5站点枪型，WeaponInventory新增显式站点奖励分支并保留历史固定reward；WorldSites/FrozenSettlement继续拥有实际携带与唯一入库。FieldActor持有按实例绑定的WeaponMagazine，Expedition按活跃模拟推进并在原成功攻击提交后扣弹，HUD只读。世界8扩展原快照，不增加战斗/保存/奖励owner；见[弹匣与掉落合同](design/m7-weapon-01.md)。

TaskActions只生成/校验V4任务描述并投影真实目标进度；DailyActions保留V1/V2/V3认证分支。Expedition沿原站点/刷怪owner推进空投工作和有界一次性压力，SortieSnapshot世界6保存同一task_event及原敌人事实；FrozenSettlement从报告计算任务摘要，EnemyState只对111开放经校验的last_day.task。没有新保存或收益owner；见[任务合同](design/m6-rogue-02.md)。

RogueActions只拥有每日V1配置与确定性描述，RogueLayout只拼装/校验值布局并构造StreetLayout；现有Main/ProductionProgress/FrozenSettlement/Snapshot继续拥有选择、写入、结果和恢复。data_version2与世界version3显式绑定完整generated；旧规则与旧历史认证独立保留，普通入口在消费前拒绝旧途中。空间描述统一驱动原绘制、寻路、遮挡和交互，详情见[生成合同](design/m6-rogue-01.md)。

PlayableEntry只提供统一启动配置、固定独立进度路径和旧开发入口选择。Main仍组合原营地/任务/Expedition/ProductionProgress；player_mode只改变界面文案与开发控件可见性。ProductionProgress仅新增精确canonical试玩路径的许可，既有隔离路径和严格数据校验保留；不复制事务或结果计算。详见[试玩边界](design/m6-playable-01.md)。

根目录为Godot2D项目，严格使用.godot-version。Main组合已有营地、任务、界面、声音与保存服务；Expedition拥有真实世界推进、导航、LOS、刷怪和攻击判定。

FieldActor持有身份、生命、路径及意图；EnemyBehavior只实现类型状态，EnemyRules只定义项目暂行参数。ActorVisual/MotionAtlas/MotionHands只派生方向、姿态、图层和握点，不产生伤害或修改AI。脚底Y排序和权威枪口几何仍由原链使用。

M5-CONTACT-01由Expedition在原暂停/模拟阶段内调用无状态FieldContacts，按稳定身份执行有界扫掠、静态避障和队友让位。FieldActor提供路径意图，最终实际位移再送入ActorVisual。绕行是已有可保存路径，不增加隐藏决策状态；近战28px及伤害/冷却保持。新世界BUILD及三项表现缓存的兼容边界见[接触设计](design/m5-contact-01.md)，旧历史认证与旧途中恢复分别处理。

NormalInfectedV1只预载普通感染者五张源图，派生帧、镜像、固定作者脚点和显示比例；原ActorVisual时钟仍拥有攻击/受击/死亡状态。方向滞回、短停保相位和平滑接触偏移仅用于普通感染者；其他角色保留MotionAtlas路径。无新快照字段，不改变逻辑脚点、枪口、LOS或伤害。[映射与边界](design/m5-art-infected-01.md)

RunSave、ProductionProgress、RunTransaction、ReceiptJournal和SortieSnapshot是原数据/事务边界；没有第二套动画保存器。冻结结果、死亡、READY、单次领取与暂存代次均由原owner提交。旧格式与111分开，未知/不兼容记录严格拒绝。收据外层使用显式 BH_EXACT_JSON_V1 精确传输，历史业务/资源/世界指纹保持；见[编码合同](design/p0-record-hash-02.md)。生产门禁仍由独立审阅决定。

公共测试只用独立新数据；不包含内部原始证据或玩家档案。[验证范围](VALIDATION.md)说明与内部完整矩阵的区别。

CombatActions显式分派generated8/rules9/world11，旧M8及更早投影保留。CombatRuntime只在Expedition原步进内组合CombatPatternsV1/ToxicV1，前者只出几何计划，后者只出定时固定目标批次。原FieldActor/PersistedDamageGate、GrowthInputs/XpInputs、EncounterRuntime和RunTransaction分别继续拥有生命/死亡、唯一XP、首领致命和磁盘。CombatEnemyRules核新出生与毒气释放身份；SortieSnapshot严格保存模式/动作/毒区，不引入第二结算器或存档写者。
