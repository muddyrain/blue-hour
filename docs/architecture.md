BuildItems与BasicSupport只作纯定义/规划/只读组件；BuildActions显式generated7冻结出发构筑，BuildState推演原营地库存。BuildAuthority生成完整支援前/后态证明，原RunTransaction journal原子持久化后由Expedition应用，FrozenSettlement仍是唯一归航结果owner。旧模式独立认证；详见[构筑合同](design/m8-build-01.md)。

ReceiptJournal的R1缓存仅复用完整原文和相邻原文的纯认证证明；每次仍重读真实文件、检查全链与binding，不缓存当前营地/ACK权威。FreezeProfile仅为默认关闭的聚合计时；没有新保存格式或异步owner。

NeighborhoodActions/Layout/Art提供V3尺寸、主题和每类门尺度；实体院墙与所有空间消费者读取同一StreetLayout。DailyActions保留V1/V2认证，新增规则4/世界5，不另造保存或奖励owner。见[尺度与拓扑](design/m6-world-02.md)。

WorldActions/WorldLayout/WorldSites提供V2有限街区、站点预算与事实校验；DailyActions按版本保留V1解释。BuildingLibrary拥有素材和门锚点，BusJourney只读已登记行动/冻结结果并推进表现。原数据owner继续唯一保存；详见[街区合同](design/m6-world-01.md)。

# 架构与所有权

M15 的 LevelPolicy/LevelSummary 只生成局部任务用途、最终导航路线及只读卡片事实。新旅程在 build6 的 worldgen 标识中显式选择 version2/BH_LEVEL_V1，原 marker1/policy3 与 layout4 独立保留。布局、站点和摘要一起有界重试；原保存、工作、伤害、救援与结算 owner 不变。新成功纯结果仅按完整输入复用原 ValueProofCache，见[任务关卡合同](design/m15-level-01.md)。

M14 R2 的 StreetModuleArt 只定义新画布/门/墙脚元数据，WorldgenGeometry/Dressing 冻结art_revision3、局部门面和两条院墙脚，FieldProp/WorldgenGround/Furniture读取同一几何。旧layout4不走新路径。ValueProofCache按完整当前值与私有深拷贝的原生递归精确比较复用纯计算结果；ReceiptJournal每次重读原文件字节，命中后仅省解析与历史深拷贝，对外仍隔离返回。FrozenSettlement仍是唯一结果owner；没有新保存格式、异步写者或提前ACK。

CampaignRules只提供纯阶段/显示，CampaignActions在原V5之上冻结V6阶段及导航验证首领定义。BossBehavior只产生稳定请求，BossWarning只读绘图；EncounterRuntime在Expedition内调用原攻击、伤害、刷怪与击败/XP owner。FrozenSettlement在原结果内推演journey.campaign，ProductionProgress确认提交后才成为持久结果；世界9保存同一首领和请求事实，没有另一个存档或归航结算器。旧111无campaign字段时保持原模式，历史指纹分支保留。见[短局合同](design/m8-run-01.md)。

M18 普通新旅程使用 `journey.campaign` V2 `investigation_v1`。InvestigationActions 选取现有行动预算，给调查装备行动增加显式版本、线索和真实主站点绑定。既有世界与报告只记录站点是否完成，冻结结算验证本日行动和站点事实，再推演有来源的营地线索。原持久确认使进度生效。两份线索齐备后由原生成器提供原终局描述；`short_v1` 的四次准备继续独立认证。

M19 新旅程显式选择 V3 `mission_v1`。普通任务用冻结 `mission_policy:1` 认证成对近点、露天装备或深入调查，候选按原身份确定性生成。选卡从实际站点、可达路径和原事件读取主收益、路线与风险。调查主点结算使用真实完成事实，沿用 M18 的线索事务。新能力来源在旧营地 JSON 中可按精确的序列化投影校验，冻结行动和收据继续使用完整精确证明。V2 `investigation_v1` 与 `short_v1` 各自认证历史。

M20 的蓝调底图与局部主题只服务正常试玩的标题、营地和选卡。营地从原库存、口粮、队伍和收据结果投影界面，选卡直接读取原冻结行动及站点。Main 仍接收原出击意图并调用原事务；慢路径在出击已成立后淡出底图，失败回到可读的原错误和可用焦点。画面与焦点状态不进入行动、存档或世界指纹。

M25 新旅程在 `mission_v1` 营地保存 `action_policy: 1`。InvestigationActions 用旅程种子与日期决定备选类型，复用原队伍资格、导航认证和任务来源。补给、调查和终局保留原行动所有者。旧标记和已冻结行动仍按原策略重建。选卡从同一营地口粮、冻结站点和角色定义读取收益与条件。

M27 的新旅程通过 campaign.midgame 选择设施规则和住宅院生成。CampEdit 认证一次性建设和扣款，WeaponInventory 共用工坊报价，FrozenSettlement 按已建成设施推演独立的供粮账本。住宅院由独立行动修订冻结真实门洞、搜刮点和路线。旧行动与旧收据按原值认证。终局提示读取现有击败、集合和确认状态。

M28 新旅程通过 `campaign.finale_policy` 选择河堤泵站。PumpStationAction 冻结固定地图和零战利品的停机工作点，原派工事实同时驱动控制柜、首领可见性和胜利资格。泵站的 encounter V2 严格校验冲锋状态与真实障碍，旧 encounter V1 保留原字段和判定。原伤害、死亡、暂存、结算与收据继续负责持久化。胜利画面只投影已提交泵站收据。[M28 设计](design/m28-finale-01.md)。

M29 以 `campaign.rare_policy` 选择备选位策略，只有稀有行动附带同版本的冻结标识。InvestigationActions 认证当日候选，ExplorationActions 从原行动来源重建地图和站点，LevelSummary 测量指定追加站点的返程路线。冷库沿用灯光与室内派工，军需站沿用装卸院与一次性露天回收事件。实际携带、暂存及唯一入库由原世界和事务链负责。[M29 设计](design/m29-rare-sortie-01.md)。

M30 的 OpeningBuild 认证新建营地的单件领用。初始营地收据和原绑定固定方案、道具、旅程及根身份。BuildState 在原出击来源验证前计入已领用道具，普通装备行动以显式策略冻结被动掉落。槽位编辑与归航沿用原事务，旧营地保留原来源校验。[M30 设计](design/m30-opening-build-01.md)。

M31 的 CatalogProgress 在 ProductionProgress 持有进度写入权时，从绑定到原收据链的已确认结果投影两个跨局里程碑。新旅程登记冻结已验证的解锁指纹，普通装备行动按该资格冻结 BuildItems 掉落策略。图鉴只读投影。CombatRuntime 从实际槽位读取周期毒伤因子，继续使用原伤害门禁与 ToxicV1 确认。[M31 设计](design/m31-meta-progression-01.md)。

M32 由新旅程策略与已签行动显式启用尖啸者。CombatRuntime 在原普通生成结果上替换一次，并在原玩家攻击之后推进读条。叫群按原街口安全规则一次性兑现，继续使用同一敌人序号和伤害路径。新行动使用 `combat.version: 2` 保存唯一身份、剩余时间和整批结果，原世界及收据继续按其冻结输入认证。[M32 设计](design/m32-threat-01.md)。

WeaponActions只在原TaskActions描述上冻结V5站点枪型，WeaponInventory新增显式站点奖励分支并保留历史固定reward；WorldSites/FrozenSettlement继续拥有实际携带与唯一入库。FieldActor持有按实例绑定的WeaponMagazine，Expedition按活跃模拟推进并在原成功攻击提交后扣弹，HUD只读。世界8扩展原快照，不增加战斗/保存/奖励owner；见[弹匣与掉落合同](design/m7-weapon-01.md)。

M33 在新旅程及符合条件的冻结行动上加版本标记。WeaponInventory 认证长管步枪的新来源分支，WeaponModifiers 从同一实例派生单个战斗词缀。Expedition 沿原射击和击倒归因应用穿透或补弹，WeaponMagazine 继续保存实际弹量。旧世界保持原兼容指纹。[M33 合同](design/m33-weapon-build-01.md)。

M34 由新旅程和已确认入队的出发身份认证急救资格。FirstAidV1 计算合法目标，Expedition 在原模拟步触发，BuildAuthority 和 RunTransaction 用原支援证明提交。一次性使用状态和实际恢复量来自同一接受事实，生命守恒与归航由原核验链负责。[M34 合同](design/m34-survivor-role-01.md)。

M35 在显式启用的新旅程中为备选槽普通装备行动冻结风险结果。SortieRiskV1 复用已认证布局和 LevelSummary，按最终往返和可选站点证明决定是否交付大型深入回收。InvestigationActions 继续认证当日完整行动，WorldSites 与 FrozenSettlement 负责原携带和归航确认。[M35 合同](design/m35-sortie-risk-01.md)。

M36 用营地已确认归航数冻结跨日敌情。CampaignPressureV1 提供版本化间隔倍率，Expedition 与 SortieSnapshot 的敌情核验读取同一冻结标记。原昼夜阶段继续由 ThreatDirector 根据现场时钟计算，收据与归航仍由原事务链确认。[M36 合同](design/m36-campaign-loop-01.md)。

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

SearchAssignments只拥有稳定member_id↔site_id与approach/working一对一关联；SearchWorkView只格式化只读状态。Expedition继续拥有导航、各站点进度、原伤害/奖励/巴士推进，TraitInputs用显式site_id认证实际完成者且保持原类别事件粒度。世界12在generated8/rules9上增加严格jobs交叉证明，支援整世界替换保持任务。旧11原格式/指纹严格恢复并保持单任务至归航，后续出击12；无第二套生成、结算或迁移写者。见[多人工作合同](design/m10-search-01.md)。

SpecialPowers只提供严格请求/激活事实与模拟时间派生；PowerActions为generated8附加显式powers1扩展，移除此字段后的原V8必须完整认证，旧分支不变。PowerState只推演原营地库存、来源与日使用事实；PowerAuthority提供世界13完整前后态证明。原CampEdit、RunTransaction/Journal、FrozenSettlement仍分别唯一拥有营地编辑、激活持久化和归航入库。FieldActor.effective_speed读取基础speed与一次派生因子，快照继续保存原基础值；Expedition分割到期步进并停敌人运动/攻击/首领时钟，ToxicV1单独保留毒区时钟。PowerSlotPanel/PowerEffectView/HUD无游戏状态owner。见[能力合同](design/m11-power-01.md)。

M12-SURVIVOR-01 在原新旅程 owner 增加独立 persona1 事实（build4），PersonaActions 仅在完整原 PowerActions 描述上追加严格目录与来源认证；五个配方不授予入队资格。World14 绑定新目录与身份，旧 World13/营地保持原格式/指纹。Actor 从不可变武器/主特长/本人配方/道具派生，疾行仍单独临时因子；PersonaViewModel 缓存不变显示来源并只读投影实时数值。共享站点进度可接力，新工作下界从当时真实参与者的最快合法因子推导，保留旧版下界和 cash/food 类别上限。参见[合同](design/m12-survivor-01.md)。

M13-EXPLORE-01 的 ExplorationLayout/Sites 只生成冻结布局、对象、预算、实际路径度量和目标定义；ExplorationActions 把原完整任务来源保留为可重建的 canonical 原任务，不以删新几何字段冒充旧地图认证。新 build5 显式持有 exploration1 标识，非终局 generated9/rules10/world15 严格相互绑定；旧build4/world14及新旅程终局仍走原分支。后道具碰撞的不可变导航证书按完整布局指纹缓存，live事实不入缓存。Expedition/SearchAssignments/WorldSites继续拥有工作与携带，原事务独占暂存/支援整世界重建/归航确认；ExplorationProp/Objectives只读。车和树干只加移动障碍，不增加LOS墙。参见[探索合同](design/m13-explore-01.md)。

M14-WORLDGEN-01 的 WorldgenGeometry 先定义道路连接及地块，WorldgenScale 集中新尺度，WorldgenLayout 只认证冻结值并复用后道具导航证书。build6/worldgen1 与 generated9 的严格 worldgen 扩展绑定，布局为5；原rules10/world15字段未变，不为编号升级人物/战斗/支援。旧build5/layout4及更旧分支原样认证，旧成长记录不接受新地图前缀。R1 WorldgenDressing 在互动道具和最终导航证书之前冻结静态环境碰撞，policy revision2 拒绝未发布的R0扩展；旧layout4保持。WorldgenGround/WorldgenFurniture/精细树/HUD只读，新建筑点击区从同一等比alpha和门锚点推导并按脚点选择；原Expedition/事务/结算owner不变。详见[合同](design/m14-worldgen-01.md)。
