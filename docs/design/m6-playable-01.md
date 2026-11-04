# M6-PLAYABLE-01：完整开发试玩

基线为公开接触候选427cbb832e39bfe4e7b08a3c605f38c1fe0f3267。PR #5未合并时，本分支以codex/m5-contact-01为base并依赖#5；不引入内部历史、不向前置分支追加代码、不合并或发布。

## 玩家流程

正常启动选择「开始试玩」，明确确认原永久死亡/缺粮规则后创建独立营地。设施提供队伍档案、资源、维修配装和食物训练；巴士打开现有三个任务选项，使用两张已有固定街区。完成真实搜集或救援，等待巴士就绪、发动、集合全部存活队员，预览冻结结果，再确认结算回营。下次启动选择「继续试玩」。三次出击只是验收样例，无新增通关目标。

任务卡展示实际任务配置的钱粮、原救援条件和风险；武器按实际搜获计算。结果显示原冻结结果的钱粮、损失、个人XP和营地状态，确认后营地提示已保存。玩家界面移除内部schema、实例/事务ID和候选编号；诊断仍在日志及显式开发入口。原有HUD、美术、声音及ANIM-02/V1/接触处理保留。

## 所有权与兼容

PlayableEntry只把默认入口解析为原有完整功能链；Main、MissionSelect、Expedition、ProductionProgress、RunTransaction继续负责原业务。不增加第二套初始数据、战斗、奖励或保存器。player_mode只派生文案和开发控件可见性。

默认进度固定为`user://playable-v1/run.enemy-v1.json`，声音设置为同目录audio.json；Mac位于`~/Library/Application Support/Godot/app_userdata/Blue Hour - 蓝时归航/playable-v1/`。ProductionProgress新增精确canonical绝对路径许可，仍要求完整生存/饥饿/敌种模式；原.local隔离路径许可保留。其他任意路径拒绝，旧默认路径不自动转换。正常启动不扫描旧文件，也不自动选备份或迁移。

原双人入口用`--bh-legacy-entry`或`tools/godot.py run --legacy-entry`；原显式功能参数保持其模式与保存边界。默认run不再生成每次启动的新进度目录；check和`run --profile .local/...`仍隔离HOME和全部输出，不接触玩家目录。

未修改BH_EXACT_JSON_V1、业务schema、binding、BUILD、认证、死亡身份、READY/ACK、唯一结算或暂存恢复合同。沿用PR #4精确收据和PR #5接触BUILD边界；旧途中档仍按原兼容校验接受/拒绝并保留原件。保存路由变更单独验稳定路径、旧文件原字节保护、失败阻塞与跨PID；不凭字段未变宣称兼容，也不重复无关强杀/锁竞争/历史矩阵。正式生产门禁仍BLOCKED。

## 当前系统验收

按最新执行要求在同一PR更新AGENTS、执行规范与任务模板。风险为GAMEPLAY/MEDIUM_RISK并附保存路由回归；仅Mac，无Windows要求。先入口/单链预检，再最终公开check和三次原业务行动、新PID继续。

可复测命令：

```sh
python tools/godot.py check --godot <pinned-godot>
python tools/playable_flow.py --godot <pinned-godot> --output .local/playable-proof-unique
# Mac后台原生GL画面，需ffmpeg：
python tools/playable_flow.py --godot /Applications/Godot.app/Contents/MacOS/Godot --output .local/playable-native-unique --native-movie
```

自动驱动只向隔离viewport发送确认事件，并调用原搜集/救援/巴士接口；按原固定步长推进世界，不修改资源、血量、位置或完成状态。真实训练消费1粮并改变下一行动的实际射击系数。第二次归航注入原before_commit_receipt故障，验证不能领资源/继续出击，再重试一次；重复确认不重复领取。三次后退出进程，新PID读取同一固定路径，对比完整营地、装备实例和旧文件摘要。

原生证据使用不接收焦点的最小化窗口与1280×720 SubViewport；源码/资源均链接最终输入，只覆盖窗口标志。画面由GL实际渲染，内部操作自动，行动模拟每画面推进6步；UI停留按原帧展示。录像标明模拟加速，不是人工试玩、显示器FPS或物理键鼠证明。无Windows、物理键鼠及人工显示观感签核；不能把本轮检查当作生产门禁通过。

原始日志、合成profile、失败原件和唯一审阅ZIP仅私有保存。不给公共PR附私人绝对路径、玩家档案、原始录像或完整历史包；媒体与版本/失败索引随私有审阅包交付。[实际结果](../VALIDATION.md#m6-playable-01mac完整试玩)
