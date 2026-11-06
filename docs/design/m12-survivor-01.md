# M12-SURVIVOR-01：幸存者组合与人物详情

基线 main `662ae1754b96eeb1bee9a4177059d050f5722787`，#16 精确已审 `ef4c0afb1d72dcf266eb6551b4649e25da9e24bf` 已普通合入。以下接口/文件所有权在实现前冻结。数值为 PROJECT_TEMP 原创适配；正式生产门禁仍 BLOCKED。

## 模式、来源与数值

新旅程 build4 在原 build3 上增加独立 `persona` 事实：`{catalog_id:"BH_SURVIVOR_PERSONA_V1",version:1,seed,members:[{member_id,definition_id,positive_id,negative_id}×5]}`。只由原新旅程入口建立；原三主 Trait/训练/XP/名册记录不变。旧 build3/World13 保持原模式，不缺字段补值、不改旧指纹。generated8 冻结同一 persona 扩展和目录策略，投影去除该扩展后必须完整通过原 PowerActions；rules9 保留，新世界14绑定该描述、完整jobs、原能力与目录兼容指纹。

组合按 seed、稳定 id/definition 和独立 `BH_SURVIVOR_PERSONA_V1|…` SHA-256 域排序，逐 crew_1…crew_5 选尚未使用的合法正负对；完整规范由纯目录策略实现。全五人配方不授予名册、出击、口粮或经验资格；只展示已出现/已揭示的人。根与行动认证时严格重算，Actor 初始化/恢复只读取已认证配方，不每帧重验种子或历史。

每项从不可变基础×原主Trait×个人适用因子×原被动×临时能力派生一次。本人枪伤1.15/近战1.20、移动1.10或0.90、换弹0.85或1.15、工作0.85或1.15；互斥三对不同时出现。原枪型/弹丸/斧起手、支援伤害、救援10秒、巴士、奖励和按cash/food类别成长不变。工作最低完成时间仅新模式按原site_facts中已完成同类别站点的真实seconds、当时真实参与者中最快主Trait/个人与被动因子推导。站点保留进度允许换人接力，不能强求最终完成者独自做满全程；未参与/晚入队者或未完成的更快空投不能降低下界。旧21秒/空投分支严格保留。

## 文件所有权与纯API

- A：原 Main、Camp/Build/Power/DailyActions、Actor/Expedition/Snapshot、TraitRules/武器与共享HUD/名册/救援接线；新 PersonaState/PersonaActions/PersonaViewModel；Git、引擎导入/UID、统一验收与交付。
- B：仅新 `src/features/persona/survivor_persona.gd`、`tests/persona_rules.gd`。无 Node/Actor/磁盘依赖，不启动引擎或操作Git/UID。
- C：仅新 `src/features/persona/persona_card.gd`、`persona_details.gd`、`persona_portrait.gd` 与 `assets/persona/*.svg`。只读UI，不启动引擎或操作Git/UID，不改共享文件。

`SurvivorPersona`：`policy()->Dictionary`；`generate(seed:String)->Dictionary` 产生上述严格4键事实，非法seed返回空；`problem(value:Variant,seed:String)->String` 严格结构/身份/版本/来源/唯一组合；`member(bundle:Dictionary,id:int,definition_id:String="")->Dictionary` 仅稳定ID读取；`recipe_problem(value:Variant)->String`；`factors(recipe:Variant)->Dictionary` 返回 `{ranged,melee,move,reload,work}`，非法输入返回空，不静默中性；合法未适用指标为1。32seed×5纯重算和包内两组已知向量、八种数值与互斥负例由B提供。

`PersonaViewModel`由A只读构造统一字段：`id,definition_id,portrait:Texture2D,primary,primary_short,name,hp,max_hp,level,alive,status,ammo,positive,negative,trait_detail,weapon_detail,reload_detail,move_detail,work_detail,sources_detail,scope,editable`，可选 `weapon_texture:Texture2D`。文本为玩家文案，无hash/实现版本。scope为camp/field/candidate；详情由真实Actor或营地装备/主Trait/配方派生，不成为状态owner。

`PersonaCard extends VBoxContainer`：`signal selected(member_id:int)`；`present(model:Dictionary,compact:bool=false)`。头像/主特长在上、姓名次级；compact目标高度≤124、宽约224，HP/等级、状态、弹匣与完整＋/－特质短行。头像或信息按钮可Tab/Enter到达；不持有修改权威。

`PersonaDetails extends PanelContainer`：`signal closed`、`equipment_requested(member_id:int)`、`training_requested(member_id:int)`；`present(model:Dictionary)`，`close()`隐藏并清焦点。内容竖向滚动、根STOP阻止点击/滚轮穿透。field显示“行动继续，可空格暂停”，无编辑按钮；camp仅活人可跳原装备/培养；candidate只读。C提供可读的portrait/header/数值/来源层级，A连接Esc优先关闭、Q/E/3焦点与Space暂停政策。

## 界面与验收

沿用M11深青Theme和角色纹理。营地左列主特长人物卡、右侧统一详情，保留原改名/配装/培养事务；出击只替换右侧队员信息和详情，不重排目标/威胁/Q/E/3/巴士。1280×720四人完整可达，小屏右列必要时滚动。救援只显示当前已揭示候选，同一来源组合贯穿确认、入队与归航；不泄漏其余池。

当前Mac固定4.7.2/Compatibility；先小范围预检，纯策略/实际伤害与位移换弹工作、真实双栋、最快合法工作组合、一次救援、有效疾行+两jobs跨PID、支援重建、旧World13/营地代表、六种代表UI、最终公开check/来源。主要正常流程不写HP/库存/成员/胜利伪造结果；受控组件明确标注。新产物仅 `.local/m12-survivor-01`，增量预算≤768MiB，保留旧原件与失败。三图、30—45秒可见1×片段、一个轻量私有ZIP及正常隔离入口；本轮Draft待审、不合并/发布。
