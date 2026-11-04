NeighborhoodActions/Layout/Art提供V3尺寸、主题和每类门尺度；实体院墙与所有空间消费者读取同一StreetLayout。DailyActions保留V1/V2认证，新增规则4/世界5，不另造保存或奖励owner。见[尺度与拓扑](design/m6-world-02.md)。

WorldActions/WorldLayout/WorldSites提供V2有限街区、站点预算与事实校验；DailyActions按版本保留V1解释。BuildingLibrary拥有素材和门锚点，BusJourney只读已登记行动/冻结结果并推进表现。原数据owner继续唯一保存；详见[街区合同](design/m6-world-01.md)。

# 架构与所有权

RogueActions只拥有每日V1配置与确定性描述，RogueLayout只拼装/校验值布局并构造StreetLayout；现有Main/ProductionProgress/FrozenSettlement/Snapshot继续拥有选择、写入、结果和恢复。data_version2与世界version3显式绑定完整generated；旧规则与旧历史认证独立保留，普通入口在消费前拒绝旧途中。空间描述统一驱动原绘制、寻路、遮挡和交互，详情见[生成合同](design/m6-rogue-01.md)。

PlayableEntry只提供统一启动配置、固定独立进度路径和旧开发入口选择。Main仍组合原营地/任务/Expedition/ProductionProgress；player_mode只改变界面文案与开发控件可见性。ProductionProgress仅新增精确canonical试玩路径的许可，既有隔离路径和严格数据校验保留；不复制事务或结果计算。详见[试玩边界](design/m6-playable-01.md)。

根目录为Godot2D项目，严格使用.godot-version。Main组合已有营地、任务、界面、声音与保存服务；Expedition拥有真实世界推进、导航、LOS、刷怪和攻击判定。

FieldActor持有身份、生命、路径及意图；EnemyBehavior只实现类型状态，EnemyRules只定义项目暂行参数。ActorVisual/MotionAtlas/MotionHands只派生方向、姿态、图层和握点，不产生伤害或修改AI。脚底Y排序和权威枪口几何仍由原链使用。

M5-CONTACT-01由Expedition在原暂停/模拟阶段内调用无状态FieldContacts，按稳定身份执行有界扫掠、静态避障和队友让位。FieldActor提供路径意图，最终实际位移再送入ActorVisual。绕行是已有可保存路径，不增加隐藏决策状态；近战28px及伤害/冷却保持。新世界BUILD及三项表现缓存的兼容边界见[接触设计](design/m5-contact-01.md)，旧历史认证与旧途中恢复分别处理。

NormalInfectedV1只预载普通感染者五张源图，派生帧、镜像、固定作者脚点和显示比例；原ActorVisual时钟仍拥有攻击/受击/死亡状态。方向滞回、短停保相位和平滑接触偏移仅用于普通感染者；其他角色保留MotionAtlas路径。无新快照字段，不改变逻辑脚点、枪口、LOS或伤害。[映射与边界](design/m5-art-infected-01.md)

RunSave、ProductionProgress、RunTransaction、ReceiptJournal和SortieSnapshot是原数据/事务边界；没有第二套动画保存器。冻结结果、死亡、READY、单次领取与暂存代次均由原owner提交。旧格式与111分开，未知/不兼容记录严格拒绝。收据外层使用显式 BH_EXACT_JSON_V1 精确传输，历史业务/资源/世界指纹保持；见[编码合同](design/p0-record-hash-02.md)。生产门禁仍由独立审阅决定。

公共测试只用独立新数据；不包含内部原始证据或玩家档案。[验证范围](VALIDATION.md)说明与内部完整矩阵的区别。
