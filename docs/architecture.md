# 架构与功能边界

这是内容基线 `edf9bd9` 的公开架构摘要。根目录 Godot 2D 工程使用类型化 GDScript、显式依赖和按功能组织的模块，入口为 `src/app/main.tscn`。引擎版本由 `.godot-version` 固定。

## 所有权

```text
main / World
├── 营地快照与界面：幸存者、武器、行动地图、声音设置
├── Expedition：唯一的本局时间、单位、搜集与撤离状态
│   ├── StreetLayout：绘制、门口、障碍、导航与射击几何
│   ├── FieldNavigation / FieldActor：路径与单位运行状态
│   ├── AttackRules：目标合法性与枪线判断
│   ├── ThreatDirector / ThreatRules：同一 elapsed 下的增援阶段
│   └── Expedition HUD：只读状态并发出玩家意图
├── WeaponInventory / CampEconomy / SurvivorRoster：值校验与营地事务
├── GrowthInputs / SurvivorGrowth：真实行动记录，未知成长字段
└── RunSave：v5 读写、迁移保护、备份与失败恢复边界
```

`main` 拥有营地状态；出击取得深复制的队员/装备快照。界面发请求而不直接加钱、发武器、修改伤害或写档。一次回营事务统一接受正式结果，防止重复入账。

## 地图与攻击

StreetLayout 是门口、建筑占地、静态障碍与射击几何的坐标源。两张地图共用同一场景与战斗链。AttackRules 供选敌和实际开火共同判断，命中后产生真实生命变化与音画反馈；屋顶淡化不改变前墙是否挡枪。

FieldNavigation 负责合法路径，不替玩家决定目标。青禾市场货运站的地形候选只改变该搜集点附近的空间，不新增敌人近身出生或穿墙攻击规则。更多行为和限制见[战斗与夜间](features/combat-and-night-pressure.md)。

## 时间、搜集与巴士

Expedition 使用 ACTIVE、ENGINE、BOARDING、FINISHED。发动不改编队目标；BOARDING 阶段的显式集合请求才安排去往巴士的合法路径。到场状态由实际位置与工作状态计算，HUD 不维护另一份虚假的集合人数。

搜集员的当前工作意图独立保留，完成或手动取消后回到最新归队目标。暂停时位置、战斗、增援、搜集与发动计时均停止；意图和镜头仍可操作。FINISHED 后不继续记伤害或重复结算。见[巴士撤离](features/bus-evacuation.md)。

## 营地、装备与行动记录

武器配置和表现分开，库存按实例校验唯一归属。维修是有确认和持久化边界的营地事务；同一武器不能由两名成员同时持有。名字/呼号、装备与个人记录使用稳定身份关联。

行动记录来自本局真实致死命中，按成员、武器实例和时间保留有限明细；它不计算经验。人物等级、经验与特性字段保持未开放状态，不补造旧任务经历。见[营地与配装](features/camp-and-loadouts.md)。

## v5 与写盘

RunSave 校验整个营地快照及 schema/version。v1–v4 读取先在内存迁移，首次写入新版前保护有效旧主档及不同的有效备份原字节；v4 迁移只补空成长字段和行动明细，不重置呼号、伤情、资源或库存。

正式边界是回营和确认营地修改。声音设置独立保存。出击中途、结果预览、练习、镜头和威胁状态不保存；此快照没有持久化的局内死亡检查点或事务恢复系统。见[保存与恢复](features/save-and-recovery.md)。

## 检查与公开维护

`python tools/godot.py check` 执行导入、无界面规则/真实组件回归、HUD 双尺寸检查、资产校验与 Windows 文件锁保护。合成的 Blue Hour 历史版本夹具存于 `tests/fixtures`，不依赖原作存档或完整历史证据。

保留的 B/C ownership audit 需要对应内部历史；接敌档案独立审计需要调用者提供完整归档。这些专用历史工具不等于公开根的通用验收，不由标准 check 调用，也不能用缺少的历史结果宣称通过。

未来公共分支以公共提交为祖先，按白名单投影经审核的内部变化。首次公共根不连接内部历史；不要整体推送内部 refs。协作与数据保护见 [AGENTS](../AGENTS.md)。
