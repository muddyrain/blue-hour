# M10-SEARCH-01：多人工作合同

经典 Deadly Days 的本机观察提供机制方向；以下细则是 PROJECT_TEMP 项目适配。每成员至多一栋，每站点至多一人；没有留守名额、同楼加速、任务队列或新奖励 owner。

## 接口与单目录所有权（实现前冻结）

- A：Git、原 Expedition/Snapshot/FieldProp/HUD/RescueTarget 接线，支援/巴士/持久化、版本与全部引擎验收、交付。
- B：仅新 `src/features/search/search_assignments.gd`、`tests/search_assignments.gd`。不操作 Git/引擎/UID。
- C：仅新 `src/features/search/search_work_view.gd`、`tests/search_work_view.gd`。只读表现/格式化，不操作 Git/引擎/UID。

`SearchAssignments` 为 RefCounted，无 Node/磁盘/Actor 依赖。状态为 `{version:1, assignments:[{member_id:int,site_id:String,phase:"approach"|"working"}]}`，快照按 site_id、member_id 稳定排序。API：`assign(member_id:int,site_id:String)->bool`、`begin(member_id:int)->void`、`release_member(member_id:int)->Dictionary`（返回被释放行或空）、`member_for(site_id:String)->int`（0表示无）、`site_for(member_id:int)->String`、`phase_for(member_id:int)->String`、`ordered()->Array[Dictionary]`、`snapshot()->Dictionary`、`restore(value:Dictionary)->void`。静态 `problem(value:Variant,member_ids:Array[int],site_ids:Array[String])->String` 严拒结构/重复/缺失身份/非法phase；`pick(candidates:Array[Dictionary])->int` 仅从 `{member_id,distance,reachable,available}` 选可用可达者，按距离/member_id。A负责完整快照的生命、保护、位置、路径、站点完成/进度及救援占用交叉校验。

`SearchWorkView` 只读静态格式化：`short_site(title:String,number:int)->String` 给同类建筑稳定短名；`actor_status(phase:String,site_label:String,outdoor:bool)->String`；`building_text(member_id:int,call_sign:String,phase:String,outdoor:bool)->String`；`notice(code:String,site_label:String,member_label:String="")->String`，code为assigned/cancelled/no_idle/unreachable/completed。C可补纯只读便利函数；不新增常驻面板或状态owner，A连接现有标签/进度条。

## 保存与兼容

只增世界12，任务 generated8 / rules9 / M9营地与冻结掉落不变。世界12保存所有任务，站点进度仍由原 sites 保存；旧 worker/active_site 仅保留为固定0/空的保留字段以避免通用验证结构重写，世界12必须有 jobs，缺失严格拒绝。旧世界11先按原格式严格校验，显式按旧 worker/active_site 和真实Actor工作状态映射零或一个运行任务；该途中仍按世界11/原兼容指纹保存，保留单任务模式至本次归航，下一次正常出击启用12。已搜事实、路径、掉落与奖励不重算。旧营地/归档保留，不写原件迁移；较早模式继续原单任务规则。

暂停停表；支援 before/after 同时携带任务与各站点进度。工作到达后沿原隐藏/户外可见政策，取消失效斧起手。取消保留进度，死亡仅重置自己的未完成进度。稳定顺序逐项完成，首次失败暂停即停止其余处理。原伤害、成长、掉落、支援事务与归航结算 owner 不变。

## 生命周期与验证边界

派遣先排除死亡、隐藏、其他建筑/救援占用，再验证原导航路径及入口终点；已在入口的成员使用单点路径。无空闲与无人可达分别提示，不抢人。正常移动只改未工作成员，取消/完成按最新队伍目标归队，巴士集合仍等待所有存活参与者。室内隐藏保护、户外可见受伤与永久死亡沿原 owner；接触挤离只释放对应户外任务。实际进入工作时清路径并取消不能继续的斧起手。

任务按稳定 site_id 顺序处理，Trait 搜集事件仍保留原类别粒度和数值；新显式 site_id 参数只认证本次完成者的实际站点。第二项确认失败时，保留第一项已确认奖励，仅回退该次未确认进度增量，立即暂停并停止本帧剩余推进；严格 sites.searched/progress 合同不变。

世界12除纯分配模块的结构/重复/已知身份校验，还交叉认证：活人、未完成站点、室内/户外与阶段、显隐、入口位置、路径与游标、所有工作者都有对应任务、救援没有重复占用。支援接受后的世界重建保留全量任务/进度。不存在缺字段即空闲的兜底。

`python tools/search_flow.py --godot <固定引擎> --output .local/<新目录> --party-view` 在Windows依次跑正常两人点击/局部取消/新PID精确恢复与归航、受控室内治疗/完成失败、户外原永久死亡门禁、救援互斥及原生三四人组件。最后一项明确是受控名册/合法起点/无背景刷怪的显示与派工证明，不是招募或旅程保存证明。真实EXE窗口输入/短片另验，不能由源码脚本替代。
