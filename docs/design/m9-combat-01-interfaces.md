# M9-COMBAT-01 冻结合同

基线 main 6b2dfd14ab6fe250d62c22d96be54f6d223b09b8，含已审 #13 f937652。单目录 D:/my-code/blue-hour；分支 codex/m9-combat-01；A唯一Git/引擎操作者。临时增量预算1GiB；不碰真实进度。

A拥有所有现有文件与combat_v1主接入、版本/来源/持久化/生命/XP。B仅拥有combat_v1/weapons、assets/combat_v1/weapons、tests/combat_patterns_v1.gd；C仅拥有combat_v1/toxic、assets/combat_v1/toxic、tests/toxic_v1.gd。B/C禁止Git写、引擎、project/UID写与全流程。

## B接口
CombatPatternsV1纯静态RefCounted，POLICY集中附件数值；axe_plan(origin:Vector2,heading:Vector2,targets:Array[Dictionary],obstacles:Array[ShotObstacle],reach:float=50.0)->Array[Dictionary]；shotgun_plan(origin:Vector2,muzzle:Vector2,heading:Vector2,targets:Array[Dictionary],obstacles:Array[ShotObstacle],reach:float=150.0)->Dictionary。targets行{id:int,foot:Vector2,alive:bool,available:bool}；斧输出{id,hits:1}；枪输出{targets:Array[{id,hits}],rays:Array[{from:Vector2,to:Vector2,id:int}]}。脚点严格范围；纯几何射线在HIT_HEIGHT=28平面。墙/圆边界与旧AttackRules一致。只读CombatWeaponVisualV1由A调用present(mode:String,heading:Vector2,phase:String,progress:float)->void，可挂ActorVisual；反馈由A触发，不产生伤害。自行提供原创SVG与使用短说明。新霰弹逻辑射线起点由CombatEquipment.shot_origin取脚点命中平面，枪口仅绘制正向弹迹。A保存斧起手/方向/序号，处理扣弹/聚合伤害/XP。

## C接口
ToxicV1纯静态RefCounted，POLICY与weights集中附件值。initial()->Dictionary返回{version:1,sequence:0,casters:{},zones:[],releases:[],pending:{}}。A传实际空间，C提供纯plan(state:Dictionary,delta:float,casters:Array[Dictionary],members:Array[Dictionary],obstacles:Array[ShotObstacle])->Dictionary，返回{state:Dictionary,hits:Array[Dictionary]}。caster行{id:int,foot:Vector2,alive:bool,available:bool}；member相同。hit包含zone_id,tick,member_id,member_point,amount，pending在state中保存当次固定目标与已提交事实；由A逐目标通过原PersistedDamageGate应用后调用ack(state:Dictionary,hit:Dictionary)->Dictionary；失败暂停，不重新选目标。落点/位置编码Array[float]以便原精确JSON。problem(state:Variant)->String严格字段/阶段/时间/计数，源敌死亡后保留release事实。只读ToxicVisualV1.present(state:Dictionary)->void、advance(delta:float,active:bool)->void；轮廓原创SVG/部件由A挂实际毒气者。C应说明停走的state字段。起手锁点不追踪，先玩家攻击再plan；区域最多2，活毒气者最多1由A刷怪约束。

新旅程显式combat_v1标记；generated8/rules9/world11，旧generated7/rules8/world10及更早完全保留历史定义投影。旧两枪MAGAZINES与Definitions不原地扩表；新定义单独表/显式派发，旧指纹保持。新drop version2只新模式读。新世界保存combat状态；旧模式不补新内容。不新增保存/结算owner。
