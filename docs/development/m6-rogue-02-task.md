# M6-ROGUE-02 · Mac 接续记录

任务：四种任务在卡片、实际站点/成员、行动进度和归航结果中绑定；空投只触发一次有界增援，暂存继续保留同箱/进度/携带/敌人。用户授权依次合并 #5—#9，再实现、提交、推送并创建 Draft PR；新 PR 不合并、不 Release、不删除历史。

基线：远端 head 与附件五个已审 SHA 一致。按 #5→#9 调整 base 到 main，逐步核自身 diff 与合并后 tree。merge commit 分别为 `f9ac97d`、`8564b73`、`fb9701c`、`96ad353`、`e5ffe97`。最终 main `e5ffe979dd59068536efa81e05ed87f2d618c540`，tree `455dc1034eeebf9d862fd5c14c26e5af0a6b3c9b` 与 #9 完全相同；从该点建 `codex/m6-rogue-02`。原工作区干净，无 Godot/验收写者；不使用额外克隆或 worktree。GitNexus 不可用，使用原生 Git；GitHub 操作使用连接器。

风险：PERSISTENCE/HIGH_RISK。扩展 DailyActions/WorldSites/Expedition/SortieSnapshot/FrozenSettlement 原链，不增加保存、奖励、死亡或 ACK owner。V4 描述/规则5/世界6、目标与单次事件需定向负例、精确往返、跨 PID、部分收益、真实死亡和唯一确认验证。未修改的旧编码/锁/强杀矩阵不整套重复。只验当前 Mac；Windows 历史结果保留原条件，不作为本轮新结果。

环境：Godot `4.7.2.stable.official.ed1daf0bf`，GL Compatibility，1280×720 的独立 SubViewport。只使用 `.local/m6-rogue-02` 下合成 profile；保护用户进度及历史 `.local`。本轮预算 1 GiB；起始 `.local` 约 2.2 GiB、可用约 5.6 GiB。没有安装或运行原作，不带入 Windows 包、缓存或玩家存档。

预检：固定引擎导入与既有三尺寸 `closeout_view` 通过，确认稀疏灯/浅盆、道路提示和巴士布局。后续以原 UI Enter 输入和既有 search/rescue/bus 意图推进，不直接设完成/奖励/位置。死亡负例单独复用旧夹具：只抑制指定对象开火、真实路径走出旁人射程，普通敌人和原伤害写者实际确认永久死亡；不注入 HP/伤害或奖励。

返工保留：首次驱动错误读取途中 `inspect().receipt`（原接口按合同阻塞）改为原事务只读 recover；JSON 数字恢复中的新版本数组匹配改为数值比较；新摘要在111 owner验后只读投影，旧 last_day 白名单不变；空投12秒工作的 Trait 来源同时使用版本化站点时长及专属最低时间。所有失败原件保留在本地，不公开 profile。

原生媒体：主窗口无法直接隐藏，窗口焦点与系统前台身份需分开记录。任何启动/焦点失败原件保留，先解决后台驱动再采集最终媒体。无 OS 键鼠输入；人工手感、显示 FPS 与正式视觉签核不在本轮范围。

收尾：公开33组与80个资源文件通过；因首次Python缺Pillow，安装隔离12.3.0后重试。复审接受并修正非隔离数据测试、新结果增援ID上限及损坏站点事实校验顺序；另补旧规则拒绝新摘要。结果39项、旧摘要10项、6套原始记录新认证与原字节保护通过，最终只读复审clean。收紧结果认证后重新通过必需检查，并重采空投原生暂存/恢复与78.233秒1×模拟影片。所有失败日志、原profile/备份保留；临时启动器硬链接/探针副本已删除，固定原引擎未动。

本轮没有Mac可玩导出，不安装导出模板；准确启动方式为 `python3 tools/godot.py run --godot /Applications/Godot.app/Contents/MacOS/Godot --profile .local/m6-rogue-02-demo`。该命令创建独立试玩数据，后续从游戏内继续同目录。公开提交沿用该公共分支已公开的GitHub隐私署名，不引入本机另一邮件身份；不改全局Git配置。

计时：任务计时器只记录显式 UTC 区间。首段 inspection `02:01:17Z—02:05:42Z`；随后实现与驱动交错，开始正式 implementation 计时前的部分实施未记录，不补填。完整任务、隐藏推理、token、重连归因均 UNKNOWN。最终阶段/验收身份与耗时见本地交接报告。
