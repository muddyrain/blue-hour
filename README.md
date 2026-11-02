# 蓝时归航 · Blue Hour

Godot 2D 单机 Windows 生存原型。带领幸存者穿过街区，搜集物资、守住队友，再集合至巴士归航。

**开发源码快照，截至 M5-ANIM-01 动画原型。不是正式发行版。** 动画阶段为 GO-ANIM-PILOT；正式生存发布门禁为 **BLOCKED / NO-GO-PRODUCTION**。已稳定复现 `RECORD_READBACK:RECORD_HASH` 暂存写入拒绝，尚未修复；不要用本原型承载唯一的重要进度。

![八方向动作展示](docs/screenshots/eight-directions.png)

这是受控方向展示，使用真实角色路径，并非自然刷怪。图片场景和条件见[截图说明](docs/screenshots/README.md)。

## 当前能做什么

普通默认入口仍保留双人旧旅程。下面的成长、生存和多人成果属于显式开启的**隔离111试运行**，不自动迁移旧档。

- 双街区真实寻路、墙体LOS、自动战斗、搜集与巴士全员集合。
- 单图一个救援目标，多个原创候选；确认后当场入队、交战和归航。
- 最多四名存活者，历史名册可保留五人；真实阵亡后可救援剩余候选补位，死者历史不复活。
- 本人普通XP、Trait与食物训练，营地档案、维修、配装和跨进程营地保存。
- 卡宾与长管的基础差异，独立武器实例、品质、武器等级和首批有效词条。
- 普通、疾奔、重压三类敌人及四阶段夜间混合增援；重压攻击有可规避的真实前摇。
- 五种幸存者的八方向移动/瞄准，以及持枪、移动射击、受击、倒地；敌人独立姿态与部分明确镜像。

以上人数、数值和素材均为 **PROJECT_TEMP**。夜间自然压力仍待平衡，动画仍有共帧、离散转向和贴身遮挡。查看[已知限制](docs/KNOWN_LIMITATIONS.md)及[功能与入口](docs/features/README.md)。

![自然夜间混合敌种](docs/screenshots/night-enemies.png)

## 运行与可复测检查

固定 Godot **4.7.2.stable.official.ed1daf0bf**，Compatibility 渲染器；Python 3.10+，资源检查另需 Pillow。当前验收目标为 Windows x86_64，其他平台未验。把引擎加入PATH，或使用 `--godot` / `GODOT_BIN` 指定本机引擎。

```powershell
python -m pip install Pillow==12.3.0
python tools/godot.py check --godot <引擎可执行文件>
python tools/godot.py run --godot <引擎可执行文件>
```

公开 `check` 是不依赖私有原件的复测子集：导入、默认及111主场景启动、战斗/导航/动作组件和资源检查。已知哈希缺陷以单float重现器单列为 EXPECTED_KNOWN_FAILURE；检查退出0不代表修复或通过发布门禁。完整内部恢复/强杀/历史档矩阵未随源码发布，不能把既有内部验收算成本公共克隆通过。详见[验证边界](docs/VALIDATION.md)。

显式111原型请在独立本地目录运行：

```powershell
python tools/godot.py run --enemy-trial --profile .local/demo --godot <引擎可执行文件>
```

后续使用同一目录并在游戏内选择继续。测试和上述启动器把进度、声音及用户缓存隔离在项目本地；不要复制自己的正式存档来试。旧途中暂存跨版本不能无条件读取。源码不含游戏安装包、Release或可下载EXE；可用已安装匹配导出模板的Godot编辑器自行导出。

## 操作与资料

左键地面移动、点建筑派工/取消；WASD移动镜头，滚轮缩放，空格暂停，Esc打开暂停菜单。发动巴士后仍需明确集合，全部实际存活者到达才归航。营地设施管理成员、物资、武器和训练。

[文档导航](docs/README.md) · [公开状态](docs/plan.md) · [架构](docs/architecture.md) · [素材来源](docs/ASSET_PROVENANCE.md)

代码、美术、声音独立制作；部分原创图像使用AI辅助生成，音效由数学合成。机制研究参考经典 Deadly Days，但不包含其素材、研究原件或私人证据，不声称精确复刻。当前没有 LICENSE，公开可见不等于授予外部复制、分发或商业复用许可。
