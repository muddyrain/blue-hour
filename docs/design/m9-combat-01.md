# M9-COMBAT-01：近战、霰弹与毒气 V1

从main 6b2dfd14ab6fe250d62c22d96be54f6d223b09b8开发，#13精确已审f937652以普通merge合入。单目录真实B/C文件所有权并行，A独占共享owner与Git/引擎；见[接口](m9-combat-01-interfaces.md)。正式生存门禁BLOCKED。

正常新旅程保存build version2/combat_version1，generated8/rules9/world11；旧build1/generated7/rules8/world10、short_v1和更早继续原算法/指纹，不补新装备或毒气。新武器资源独立，旧Definitions/MAGAZINES历史投影保持。

## 攻击与来源

消防斧：34伤、1秒总间隔、0.18秒锁向起手、严格<50脚点距、110°、距离/稳定ID顺序最多3目标。移动后实际重验范围/遮挡；取消仍消耗间隔。没有弹匣。霰弹：9伤×5条[-12,-6,0,6,12]射线、1.1秒、严格<150脚点距、4发/2.4秒。新霰弹逻辑射线从脚点的28px命中平面发出，实体/墙首碰撞；长枪口仅表现，不能跳过贴身目标/墙或扩射程。近到枪口后的命中只表现枪闪与聚合命中，避免倒射弹迹。

完整批量先核原XP账容量与可提交性，然后每目标一次聚合HP/致命/原实例收据/XP；一次扳机一次扣弹。原首领record_defeat绑定实际致命敌人。斧保存sequence、remaining、heading与本次committed；枪复用实例弹匣；新世界验证动作键集合精确匹配装备，不默认填失字段。

新来源drop2绑定seed/行动/站点/版本；首个行动主装备点稳定二选一新武器，后续四类等权。旧reward和drop1不变；正常搜获、归航确认、维修10、配装后生效。Lv2×1.10、quick×.90、reach×1.15各一次；斧不受射击Trait/高压弹头/快装影响。新资源完整投影纳入M9兼容指纹。

## 毒气与恢复

ToxicV1集中暂行参数与四阶段权重。64HP、26移动，<220合法视线锁点，0.9秒起手时停走且不同时接触攻击；源敌先死亡取消。投放后6秒冷却可追击/原接触攻击。半径60、寿命3秒、.75/1.5/2.25/3秒各6伤；最多1活毒气者/2活区域，满额不开始起手。旧空投/首领援军固定普通。

Expedition先玩家攻击/死亡，再投放和区域伤害，再原全灭/结束。Toxic纯计划不写HP；原FieldActor.take_damage/PersistedDamageGate与永久死亡owner提交，ack保存固定目标游标。失败暂停，下一次推进前先重试原pending，所有时钟/运动停止。已提交目标不重伤；死亡目标后续重叠命中安全ack。release保存稳定源ID/施放序号/当时源点与锁点，源死亡后区域继续独立存在。新世界核出生来源、合法地图/LOS、活caster集合、区域/下一tick及固定pending成员/脚点；不放宽旧敌人认证。暂停恢复立即只读刷新挥击/毒区/轮廓，不用delta0偷偷重新起手。

## 经典版依据

OFFICIAL_HISTORICAL：[2019-05 Update0.50](https://store.steampowered.com/news/posts/?appids=740080&enddate=1568884297&feed=steam_community_announcements)包含近战/远程控制区分和气体区域伤害；[2019-10官方1.1](https://store.steampowered.com/news/posts/?appgroupname=Deadly+Days&appids=740080&enddate=1571310616)讨论弹丸乘数及不随搜刮顺序改变的武器掉落。2026-11-05回读官方历史页面；只支持机制方向，未实测本机原作。

PROJECT_ADAPTATION：本文扇形/五射线/锁点毒区、首行动装备安排与模式隔离。PROJECT_TEMP：全部具体数值/权重，集中在CombatPatternsV1.POLICY与ToxicV1.POLICY。UNKNOWN：原作精确公式、现代版本全部细节及完整平衡。经典app740080，排除Roadtrip3026450；没有运行/复制原作或使用真实档。

新增SVG/部件与程序姿态为本项目原创。正常感染者步态/排序未换系统；新毒气者用原基底加肩背毒囊与施放手臂，颜色只辅助识别。范围/预警/消退只读，不产生伤害。支援按钮仅去重复Q/E并压紧，不扩HUD重做。
