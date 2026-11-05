# 架构与所有权

根目录为Godot2D项目，严格使用.godot-version。Main组合已有营地、任务、界面、声音与保存服务；Expedition拥有真实世界推进、导航、LOS、刷怪和攻击判定。

FieldActor持有身份、生命、路径及意图；EnemyBehavior只实现类型状态，EnemyRules只定义项目暂行参数。ActorVisual/MotionAtlas/MotionHands只派生方向、姿态、图层和握点，不产生伤害或修改AI。脚底Y排序和权威枪口几何仍由原链使用。

M5-CONTACT-01由Expedition在原暂停/模拟阶段内调用无状态FieldContacts，按稳定身份执行有界扫掠、静态避障和队友让位。FieldActor提供路径意图，最终实际位移再送入ActorVisual。绕行是已有可保存路径，不增加隐藏决策状态；近战28px及伤害/冷却保持。新世界BUILD及三项表现缓存的兼容边界见[接触设计](design/m5-contact-01.md)，旧历史认证与旧途中恢复分别处理。

NormalInfectedV1只预载普通感染者五张源图，派生帧、镜像、固定作者脚点和显示比例；原ActorVisual时钟仍拥有攻击/受击/死亡状态。方向滞回、短停保相位和平滑接触偏移仅用于普通感染者；其他角色保留MotionAtlas路径。无新快照字段，不改变逻辑脚点、枪口、LOS或伤害。[映射与边界](design/m5-art-infected-01.md)

RunSave、ProductionProgress、RunTransaction、ReceiptJournal和SortieSnapshot是原数据/事务边界；没有第二套动画保存器。冻结结果、死亡、READY、单次领取与暂存代次均由原owner提交。旧格式与111分开，未知/不兼容记录严格拒绝。收据外层使用显式 BH_EXACT_JSON_V1 精确传输，历史业务/资源/世界指纹保持；见[编码合同](design/p0-record-hash-02.md)。生产门禁仍由独立审阅决定。

公共测试只用独立新数据；不包含内部原始证据或玩家档案。[验证范围](VALIDATION.md)说明与内部完整矩阵的区别。
