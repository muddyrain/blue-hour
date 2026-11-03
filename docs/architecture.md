# 架构与所有权

根目录为Godot2D项目，严格使用.godot-version。Main组合已有营地、任务、界面、声音与保存服务；Expedition拥有真实世界推进、导航、LOS、刷怪和攻击判定。

FieldActor持有身份、生命、路径及意图；EnemyBehavior只实现类型状态，EnemyRules只定义项目暂行参数。ActorVisual/MotionAtlas/MotionHands只派生方向、姿态、图层和握点，不产生伤害或修改AI。脚底Y排序和权威枪口几何仍由原链使用。

RunSave、ProductionProgress、RunTransaction、ReceiptJournal和SortieSnapshot是原数据/事务边界；没有第二套动画保存器。冻结结果、死亡、READY、单次领取与暂存代次均由原owner提交。旧格式与111分开，未知/不兼容记录严格拒绝。

P0-RECORD-HASH-01候选为新日志增加RecordEncoding精确数值传输；ReceiptJournal按明确外层版本验证，新旧链均运行原业务/顺序检查。旧收据只验历史算法，binding、世界、训练和迁移中的既存业务哈希不重算。算法及旧包边界见[设计合同](design/p0-record-hash-01.md)。macOS验证不关闭Windows和完整历史安全门禁。

公共测试只用独立新数据；不包含内部原始证据或玩家档案。[验证范围](VALIDATION.md)说明与内部完整矩阵的区别。
