# 公共快照验证边界

python tools/godot.py check在新的忽略目录执行：引擎版本、导入、默认/111主场景启动、现有场景切换、武器/LOS/导航/夜间/接触伤害、505项动作、17项普通感染者稳定性、172项V1资源/状态及PNG/WAV格式/导入检查。新检查保留原行为断言，按V1布局适配帧号；仅普通感染者映射改变，不重建玩法。

known_hash_cycle.gd保留单float引擎普通 JSON 二周期，要求 MINIMAL_HASH_CYCLE=true；同时要求 BH_EXACT_JSON_V1 十次真实文件往返后 EXACT_RECORD_ROUNDTRIP=true，两条件满足才退出0。另新增 record-hash 的80项真实磁盘、混合链和严格负例检查；总检查仍只代表公共子集，不解除生产发布门禁。

完整历史存档/研究原件与录像不公开。新增 Windows 合成矩阵驱动公开，真实强杀、共享锁、跨 PID、死亡与营地优先及导出包结果单列，不能把原内部结果算成本公共 check 通过。旧公开父提交的已批准夹具保留在既有公共历史，不冒称为本轮新生成的合成数据。当前tip仅含4份手工合成v1/v2主/备份夹具（固定111或222标识），v2有完整非空口粮历史；不新增或依赖真实验收用户档。新克隆应独立执行本子集，不能沿用内部通过数字。

无界面导入/主场景启动不等于原生窗口、导出EXE或OS物理输入验收。公开投影的Mac美术对照仅作视觉参考；Windows结果在下节单列，不创建Release。公开PR的对象、清单、链接与克隆检查由同步审计另行记录。

## Windows精确收据：P0-RECORD-HASH-02

从已合并 PR #3 的公共 main 21c5c59d43259070ae743ff695d505c2c89c71ee 接入独立收据编码；没有引入私有提交祖先。最终冻结运行输入后，固定 Godot 4.7.2.stable.official.ed1daf0bf / GL Compatibility 导出一次 Windows x86_64 release EXE/PCK。只读双轴审查修正了驱动对强杀前错误、损坏屏障超时及真实死亡链的判定缺口；失败原件私有保留。

| 本轮层级 | 实际证据与结论 |
| --- | --- |
| 未修改 main | 单float二周期和合法 CAMP_REGISTERED→STARTED 的真实磁盘 RECORD_READBACK:RECORD_HASH 均复现；旧已发布记录 SHA 不变，失败 stage 保留。 |
| 最终源码 | 完整公开15组 PASS，编码80项、每个数值10次真实文件往返；原动作505/稳定性17/V1 172检查保持。25项 Python 工具测试通过。原引擎二周期仍复现，新精确编码稳定。 |
| 同一实际 release EXE/PCK | 62个独立进程案例、877项落盘断言通过，其中14次真实 Windows TerminateProcess。包括已知原始 bithex 的S1、新PID精确世界、同内容S2/S3不同代次、旧代次拒绝、ACK重试、唯一结算、三个独占文件句柄、两个写者竞争及大小写路径别名。 |
| 受影响中断与营地优先 | stage写入/flush/发布、claim/binding、结果READY/写营地/提交及训练EDIT_READY/营地写入后强杀重启通过；每次屏障要求目标PID、前置零失败与原件SHA保护。重启对照强杀前独立保存的精确world/camp真值。真实两次救援、原AI阵亡、补位至五历史四活人、后续训练与改名及新PID对照通过，旧世界不能复活或覆盖。 |
| 旧格式 | 合成v1–v5沿现行迁移接受/事务边界拒绝；坏主档与显式备份选择均保持原件。混合旧/新链新PID认证通过；旧EXE对合成新记录明确拒绝且文件SHA不变。真实内部历史原件NOT_PROVIDED。 |
| 原生渲染 | 2个实际release进程在不切换的独立Windows桌面完成暂存/恢复结果，并留PNG及固定30fps原片。只向游戏viewport发送事件，不操作用户桌面。画面归属与媒体完整性另行复核，不代表物理键鼠或显示器FPS。 |

最终EXE/release模板SHA256为d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562；匹配PCK为a025ac56cb93b4a7f18880123fb126e036737cfa3aea6ea0fbf39b85b0166262。EXE为标准模板，包版本必须用PCK一起识别。源/资源、驱动/夹具、参数/profile、引擎/模板及包SHA清单与逐案例PID/屏障/原件前后SHA仅私有留存；公开驱动可复测这些合成合同，不依赖研究档。

结论为 **HASH_COMPONENT_PASS / REVIEW_REQUIRED**，只代表本轮已知传输因果和列明矩阵。真实未提供旧档、跨机器/其他系统、物理OS输入、显示流畅性和任意断电未验。原WATCH_OPEN、ANIM03_CONTACT_OVERLAP_OPEN与NO-GO-PRODUCTION保持；普通默认、业务schema、玩法数值、导航/碰撞和素材不变，生产门禁仍BLOCKED，PR保持Draft待审。

## Windows复验：WIN-PUBLIC-SYNC-04

2026-11-03验证的运行版本为e4b65ac62bfcf9792c66cbcdfad007e63c5606a9，tree为887e73b050bfaff9ecbc5b9efb3fd83e8be23057，唯一parent为541a4c9cb25330120828f6d2f92cbbbbc88c3508。本次后续提交仅改文档，运行源码、素材和导出配置未变。没有修复或引入私有P0实现。

固定Godot4.7.2.stable.official.ed1daf0bf、GL Compatibility、Windows x86_64，GPU为RTX3060/OpenGL3.3/NVIDIA591.86；Python3.13.5、Pillow12.3.0。独立克隆501文件SHA与Git blob字节相同，严格fsck通过，未复用Mac导入缓存。完整公开check退出0：13 PASS，known-hash-cycle退出1且MINIMAL_HASH_CYCLE=true；状态仍为PASS_REPRODUCIBLE_SUBSET_WITH_KNOWN_DEFECT，production_gate仍BLOCKED。

| 验证层级 | 实际结果 |
| --- | --- |
| 实际Windows EXE/PCK | 包内动作29项、菜单74项通过；五身份两枪10组真实近战/移动射击/倒地；受控诊断保持营地字节。另留41.8秒/1254帧连续原片，窗口请求1024×576，MovieWriter实际输出1280×720/30fps。 |
| 固定引擎加载同PCK | 八方向、六步态、攻击/受击/倒地、多人预览；1280×720与1024×576画面；11项viewport地面移动、暂停冻结、暂停时镜头/缩放及Esc菜单检查通过。 |
| 视觉观察 | 明暗背景和两尺寸下未见明显313.5格邻格渗色、alpha裁切或脚点突跳；贴身穿叠仍开放。受控固定步进不是显示器刷新测量。 |
| 系统输入 | Computer Use曾进入主页、营地及街区；焦点干扰/超时使完整系统输入未完成。按用户要求停止，后续在不切换的独立Windows桌面运行包内自动输入，不注入系统键鼠。物理输入仍NOT_VERIFIED。 |

引擎控制台SHA256：c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643；GUI引擎：ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424。最终EXE与匹配release模板均为d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562；PCK为d87b74762c2ef8eb837700f960eafc5af54d7aa2d0265df32edf46a5d147ea35。原始profile、过程账本、媒体及私有审阅包不公开。

失败未掩盖：跨盘模板硬链接在导出前失败，改为SHA核对的隔离复制；release模板忽略外置脚本的两次标题页录制不计视觉通过；外置战斗驱动访问已释放敌人后修正终止屏障；首次包内动作缺输出目录导致PNG失败及进程异常，补齐新目录后通过；菜单旧驱动误用于隐藏Start的营地原型产生1个夹具断言失败，切回其既有普通营地入口后74项通过。未修改产品以适配这些驱动错误，失败原件私有保留。

本轮没有整套旧档/强杀/多写者P0矩阵、自然任务全程、物理键鼠、真实显示帧率或最终美术签核。原Windows内部线保持独立且未切换；此公共分支保留Draft，未合并main或创建Release。软件层复验完成不解除RECORD_READBACK:RECORD_HASH、ANIM03_CONTACT_OVERLAP_OPEN或NO-GO-PRODUCTION。
