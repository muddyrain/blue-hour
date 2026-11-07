当前候选 **M15-LEVEL-01**：新旅程将补给食品点组织为相邻搜刮组、装备主点组织为深入路线、救援组织为可进入的住宅簇。任务卡区分实际主点收益与其他资源，并从最终导航说明绕路成本；原工作、奖励、威胁和巴士规则保持。M14 PR #19 已按精确已审 HEAD 普通合入，本轮独立 Draft 以 main 为 base，不自动合并或发布。[合同](docs/design/m15-level-01.md)。当前仅 Windows 源码及后台原生，开发验收保留同步耗时待审项；正式生产门禁仍 **BLOCKED**，新增政策 **PROJECT_TEMP**。

当前候选 **M14-WORLDGEN-01-R2**：普通新旅程商业地块接入真实画布的连续双店、共用铺装和可通行内院；同一47栋合成档的暂存与归航GUI同步回调三次均低于500ms，保留完整认证、持久ACK与唯一结算。旧 build5/layout4/world15 保持原冻结布局；未发布R1隔离档需原候选继续，R2入口使用新旅程。同一 Draft PR #19 待审、未合并。[随机街区合同](docs/design/m14-worldgen-01.md) · [Windows验证](docs/VALIDATION.md#m14-worldgen-01-r2windows)。数值均为 PROJECT_TEMP，正式生产门禁仍 BLOCKED。以下按各阶段保留历史说明。

历史阶段 **M13-EXPLORE-01**：新旅程的普通行动提供更大的小/中/大街区，加入停放车辆搜刮、果树采集与可选建筑。一个主目标和两条可选目标按真实对象显示进度；点击定位只移动镜头，仍可随时按原条件归航。旧World14/build4和终局保持原模式。PR #17已按精确已审HEAD普通合入，本轮Draft待审，不合并或发布。[探索合同](docs/design/m13-explore-01.md) · [Mac验证与已知退出问题](docs/VALIDATION.md#m13-explore-01mac)。新增数值为PROJECT_TEMP，正式生产门禁BLOCKED。以下保留历史阶段说明。

当前候选 **M12-SURVIVOR-01**：新旅程为稳定身份固定一正一负特质，营地、出击与已揭示救援对象共用只读人物详情。保留原三主特长、训练和随机掉落；旧营地/世界13保持原模式。PR #16 已按精确已审 HEAD 普通合入，本轮 Draft 等待审阅、不合并或发布。[合同与边界](docs/design/m12-survivor-01.md)。只验当前 Mac，新增数值为 PROJECT_TEMP，正式生存门禁仍 BLOCKED。

当前候选 **M10-SEARCH-01**：连续点击不同房屋可分别派遣空闲且可达的队员，全队均可参与；重复点击只取消该栋，其他工作继续。队员/建筑显示各自任务与进度，普通移动只影响未工作成员，巴士等待所有存活者。世界12保存全部分配，旧M9世界11途中保留单任务至归航，下一次新出击启用多人。[合同与兼容](docs/design/m10-search-01.md) · [Windows验收](docs/VALIDATION.md#m10-search-01windows)。数值PROJECT_TEMP，正式生存门禁仍BLOCKED。

当前 M11 开发候选接入[可装备特殊能力与紧凑出击界面](docs/design/m11-power-01.md)：新建旅程从装备站点搜获样本，归航确认后在营地单槽二选一；疾行号令为全队移动×1.5/8秒，全域冻结为敌人停行动4秒，每日共一次，快捷键3或左侧按钮释放。Q治疗/E空袭和两被动槽保持独立。目标可折叠、上中威胁、右侧纵排队员与底部紧凑巴士沿用真实状态。旧旅程继续原模式，全部新增参数为PROJECT_TEMP；本轮 Mac，Draft待审，正式生存门禁仍BLOCKED。

M9-COMBAT-01及R1已按精确审阅提交合入#14：消防斧、五弹丸霰弹、毒气感染者与原唯一伤害/恢复链保留；最小缩放空袭和晚阶段死亡起手修复保持。旧M8/short_v1仍走旧模式。

当前开发候选M8-BUILD-01 WIN-R1：装备主回收点获得本局被动、归航确认入库、营地两个可替换槽，以及Q治疗/E瞄准空袭。正常新旅程启用，旧旅程保持原模式；[构筑合同](docs/design/m8-build-01.md)。开发验收与正式生产门禁分别报告，BLOCKED保持。

# 蓝时归航 · Blue Hour

当前M8开发候选新增[第一条可通关短局](docs/design/m8-run-01.md)：正常新建后四次准备归航（筹备两次、突围两次），再挑战“突破封锁”的破阵者；真实击败、存活者经巴士归航并确认保存才获胜。新旅程使用短局，旧营地/途中保留原模式。仅Mac开发验收，依赖未合并PR #11，Draft待审，不自动合并或发布。

当前M7开发增量提供[两类稳定武器掉落与弹匣换弹V1](docs/design/m7-weapon-01.md)：卡宾枪12发/1.6秒、长管步枪5发/2.2秒，备弹无限；实际枪型随站点确定，归航后维修装备，途中弹量/换弹随同一实例恢复。PR #10已合入，以下M6内容保留对应阶段说明；本轮新Draft等待审阅，不自动合并，正式发布门禁保持。

当前开发候选新增[任务目标与行动差异V1](docs/design/m6-rogue-02.md)：食品站点、装备搜寻、幸存者生还归航、空投回收四种任务，每日提供三项。任务卡显示主目标，局内跟踪真实进度，归航分别显示完成情况与实际所得；空投约12秒回收时角色可见并可受击，一次性普通感染者压力随世界7快照继续；旧隐藏规则的空投途中保留原件并明确拒绝继续。没有任务额外奖金。本轮仅Mac定向验收，Windows不重复，正式发布门禁保留。

当前开发候选M6-WORLD-02：小/中/大地图使用同一角色与建筑尺度，商业街、住宅巷和仓储院落具有不同道路与实体院口。超市/联排门窗、连续铺装、墙脚和入口标识经过校准；部分搜刮、原暂存恢复与巴士归航链保留。见[尺度与拓扑合同](docs/design/m6-world-02.md)。依赖未合并PR #8，仍为开发试玩，正式发布门禁保持。 R1收尾改为少量稳定道路/入口道具，隐藏停车框；同值历史认证复用后，当前Windows三次大图完整冻结单步247.586/401.743/243.134ms，达到本轮≤500ms暂行目标，仍可能感知停顿。

Godot 2D 单机生存开发试玩。带领幸存者穿过街区，搜集物资、守住队友，再集合至巴士归航。

**M6-ROGUE-01：正常试玩接入每日三个行动和模块街区V1，保留完整旅程、感染者V1与接触修复。不是正式发行版。** 动画阶段为 GO-ANIM-PILOT；正式生存发布门禁为 **BLOCKED / NO-GO-PRODUCTION**。精确收据传输候选修复已知极小浮点写盘回读的因果，仍待完整审阅；不要用本原型承载唯一的重要进度。

[ANIM-02](docs/design/m5-anim-02.md)保留普通感染者转向、短停步态和贴身偏移的连续性；[普通感染者V1](docs/design/m5-art-infected-01.md)使用五个独立源方向、三向镜像和六姿态步行。[M5-CONTACT-01](docs/design/m5-contact-01.md)新增逻辑脚点分离、追击留距和队友让位。该M5历史阶段先交Mac证据；M6-WORLD-02的Windows结果见验证记录。物理输入与显示流畅性仍待验，2.5D身体遮挡仍允许。

![八方向动作展示](docs/screenshots/eight-directions.png)

这是M5-ANIM-01历史受控方向展示，使用真实角色路径，并非当前V1或自然刷怪。图片场景和条件见[截图说明](docs/screenshots/README.md)。

## 当前能做什么

正常启动选择「开始试玩」，进入营地、训练或配装，再从巴士的本日三个候选选择一项；进入选定规模与主题的街区，搜刮/救援后发动巴士并集合存活者，预览并确认结算，回营再次出击。下一次启动选择「继续试玩」。新建短局需四次准备归航与一次终局；旧旅程继续原每日循环。

默认使用固定的 `user://playable-v1/run.enemy-v1.json` 独立进度。Mac位于 `~/Library/Application Support/Godot/app_userdata/Blue Hour - 蓝时归航/playable-v1/`。不会自动读取、迁移、覆盖或回退旧进度。以下既有系统通过统一入口接入，没有另一套玩法实现。

- 每日补给、装备与合资格救援；小中大三档、三种实体道路/院落结构和不同合法建筑组合，共用绘制/寻路/遮挡/交互数据。固定双街区保留供开发回归。
- 单图一个救援目标，多个原创候选；确认后当场入队、交战和归航。
- 最多四名存活者，历史名册可保留五人；真实阵亡后可救援剩余候选补位，死者历史不复活。
- 本人普通XP、Trait与食物训练，营地档案、维修、配装和跨进程营地保存。
- 卡宾与长管的基础差异、稳定等权掉落、独立弹匣/自动换弹，保留独立实例、品质、武器等级和首批有效词条。
- 普通、疾奔、重压三类敌人及四阶段夜间混合增援；重压攻击有可规避的真实前摇。
- 五种幸存者的八方向移动/瞄准，以及持枪、移动射击、受击、倒地；敌人独立姿态与部分明确镜像。

以上人数、数值和素材均为 **PROJECT_TEMP**。夜间自然压力仍待平衡，动画仍有共帧、离散转向和贴身遮挡。查看[已知限制](docs/KNOWN_LIMITATIONS.md)及[功能与入口](docs/features/README.md)。

![自然夜间混合敌种](docs/screenshots/night-enemies.png)

## 运行与可复测检查

固定 Godot **4.7.2.stable.official.ed1daf0bf**，Compatibility 渲染器；Python 3.10+，资源检查另需 Pillow。发布前另覆盖计划发布平台；M6-WORLD-02按当前Windows范围验收，物理键鼠和人工观感仍未签核，详见[验证层级](docs/VALIDATION.md)。把引擎加入PATH，或使用 `--godot` / `GODOT_BIN` 指定本机引擎。

```powershell
python -m pip install Pillow==12.3.0
python tools/godot.py check --godot <引擎可执行文件>
python tools/godot.py run --godot <引擎可执行文件>
```

公开 `check` 是不依赖私有原件的复测子集：导入、默认及111主场景启动、战斗/导航/动作组件、普通感染者稳定性与V1资源检查。单float诊断保留原引擎 JSON 二周期，同时要求新编码十次真实磁盘往返稳定；另有 80 项精确编码和混合链回归。Windows 合成安全矩阵驱动随源码提供，结果及未验项按本轮证据报告；检查退出0不代表通过生产发布门禁，完整内部历史档不作为公共克隆已测。详见[验证边界](docs/VALIDATION.md)。

默认运行无需玩法参数，进度保存在上面的固定用户目录。开发检查仍可显式使用隔离111入口：

```powershell
python tools/godot.py run --enemy-trial --profile .local/demo --godot <引擎可执行文件>
```

后续使用同一目录并在游戏内选择继续。`check` 和显式 `--profile` 使用项目本地隔离目录，默认 `run` 使用固定试玩目录。旧双人开发入口为 `run --legacy-entry`；不要复制自己的真实进度做测试。旧完成营地保留身份继续每日行动；普通试玩在claim前拒绝旧版本途中暂存，原件保留，须用原兼容版本继续。源码不含游戏安装包、Release或可下载EXE；可用已安装匹配导出模板的Godot编辑器自行导出。


每日规则、收益范围和保存边界见[随机行动与街区V1](docs/design/m6-rogue-01.md)。后台完整验收可用 `python tools/playable_flow.py --godot <引擎> --output .local/rogue-proof`；加 `--native-movie` 在Mac后台采集，旧固定流程用 `--scenario fixed`。这些参数只供隔离验收，玩家正常启动无需玩法参数。

## 五篇独立功能说明

| 文档 | 玩家流程与当前边界 |
| --- | --- |
| [出击、搜集与救援](docs/features/sortie-and-scavenging.md) | 双地图派工、取消、单目标候选救援及当场入队 |
| [战斗、视线与夜间](docs/features/combat-and-night-pressure.md) | 三敌种、两枪比较、真实LOS与八方向原型 |
| [巴士发动与撤离](docs/features/bus-evacuation.md) | 显式集合、实际全员到齐、结果预览和提交 |
| [营地、名册与配装](docs/features/camp-and-loadouts.md) | 四活五历史、普通成长/Trait/训练、武器实例与有效值 |
| [保存与恢复](docs/features/save-and-recovery.md) | 新旧档保护、一次暂存、精确收据与途中兼容边界 |

## 玩法展示与历史版本

![历史搜集与警戒](docs/screenshots/market-scavenging.png)

**M5-COMBAT-03（edf9bd9）历史游戏截图**：正常市场搜集，不代表当前动画、成长或枪械值。

![历史救援后当场入队](docs/screenshots/rescue-join.png)

**M5-RESCUE-02历史游戏截图**：沈听澜当场加入四人行动，旧动作/HUD；呼号为人工压力测试，不是当前M5-ANIM-01截图。

营地、配装、巴士与结算等全部版本/来源和SHA见[截图索引](docs/screenshots/README.md)。仓库既有四张M5-ANIM-01图保持原字节，当前原型说明以功能文档为准。

## 开发效率工具

按实际改动与受影响合同选择当前系统检查，不因普通玩法涉及战斗自动运行完整存档矩阵。阶段计时工具仍可用，仅在工具改动时验其自身。

```powershell
python -m unittest discover -s tests/tools -p test_task_timing.py -v
python tools/task_timing.py --help
```

[执行规范](docs/development/codex-execution-efficiency.md) · [任务模板](docs/development/codex-task-template.md)

工具只记录显式可见区间，隐藏推理/完整对话耗时保持UNKNOWN；实际计时文件不随源码公开。计时工具不修改游戏或存档协议；精确收据传输另见[保存边界](docs/features/save-and-recovery.md)，正式生存NO-GO/BLOCKED。

## 操作与资料

左键地面移动、点建筑派工/取消；WASD移动镜头，滚轮缩放，空格暂停，Esc打开暂停菜单。发动巴士后仍需明确集合，全部实际存活者到达才归航。营地设施管理成员、物资、武器和训练。

[文档导航](docs/README.md) · [公开状态](docs/plan.md) · [架构](docs/architecture.md) · [素材来源](docs/ASSET_PROVENANCE.md)

代码、美术、声音独立制作；部分原创图像使用AI辅助生成，音效由数学合成。机制研究参考经典 Deadly Days，但不包含其素材、研究原件或私人证据，不声称精确复刻。当前没有 LICENSE，公开可见不等于授予外部复制、分发或商业复用许可。

M6-WORLD-02后台定向复测：`python tools/world_flow.py --godot <引擎> --native --case neighborhood --output .local/world02-proof`。Windows独立桌面不切换用户输入桌面；`--pack <最终PCK>` 使用固定编辑器引擎加载包内游戏代码，release EXE默认启动另验。
