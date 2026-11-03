# 公共快照验证边界

python tools/godot.py check在新的忽略目录执行：引擎版本、导入、默认/111主场景启动、现有场景切换、武器/LOS/导航/夜间/接触伤害、505项动作、17项普通感染者稳定性、172项V1资源/状态及PNG/WAV格式/导入检查。新检查保留原行为断言，按V1布局适配帧号；仅普通感染者映射改变，不重建玩法。

known_hash_cycle.gd是单float已知缺陷重现器，预期返回1并打印MINIMAL_HASH_CYCLE=true。工具将它标为EXPECTED_KNOWN_FAILURE；总检查退出0只表示子集符合已声明结果，**不表示缺陷修复或通过P0发布门禁**。

完整历史存档/研究证据、Windows强杀及文件锁矩阵、跨进程真实旅程证据和原始录像不公开，相关内部驱动不列为本公共check通过。旧公开父提交的已批准夹具保留在既有公共历史，不冒称为本轮新生成的合成数据。当前tip仅含4份手工合成v1/v2主/备份夹具（固定111或222标识），v2有完整非空口粮历史；不新增或依赖真实验收用户档。新克隆应独立执行本子集，不能沿用内部通过数字。

无界面导入/主场景启动不等于原生窗口、导出EXE或OS物理输入验收。公开投影的Mac美术对照仅作视觉参考；Windows结果在下节单列，不创建Release。公开PR的对象、清单、链接与克隆检查由同步审计另行记录。

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
