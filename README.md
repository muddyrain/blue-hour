# Blue Hour｜蓝时归航

Godot 4.7（GDScript）2D 斜俯视小队生存原型：营地整备 → 选择任务 → 进入随机生成街区派工搜刮、战斗、救援 → 发动巴士集合撤离 → 回营结算（食物、成长、经济/建造）→ 再出击。机制参考 Deadly Days 一类游戏，但不包含其任何素材。

> 状态：未发布原型。数值均为临时值（PROJECT_TEMP）。存档格式随时可能变化，**不保证旧存档可读**。

## 运行

引擎版本固定为 `.godot-version`（4.7.2）。

```bash
# 直接用编辑器打开 project.godot，或：
python tools/godot.py run --godot <Godot 可执行文件>
```

导航原生 helper 是**可选加速**。直接打开编辑器、运行或导出都不要求编译器；缺库、平台不匹配或加载失败时，日志 `BH_NAVIGATION fallback:` 表明使用 Godot 4.7.2 的原始 `AStarGrid2D`，仍执行完整校验（大型历史存档会更慢）。`BH_NAVIGATION native:` 表明已启用加速。不要把 Linux 的读档耗时当作 Windows 的性能保证。

macOS arm64 / x86_64 当前使用严格 fallback；仓库尚无 macOS 导出预设或已验证的 Mac helper 构建流程。可用官方 4.7.2 编辑器打开项目，Mac 读档耗时需要在 Mac 上测量。

维护者可提前构建 Linux / Windows x86_64 helper（单精度，公开 GDExtension C API）：

```bash
python3 tools/build_navigation.py <Godot> --required
# Linux 上交叉构建，或 Windows 上指定 MinGW / LLVM-MinGW 的 GCC/Clang：
python3 tools/build_navigation.py <Godot> --target windows.x86_64 --compiler <x86_64-w64-mingw32-gcc或clang> --required
```

头文件和 API 元数据由锁定引擎导出，所有产物仅在 `.local/navigation-native/`。构建工具默认在失败时报告回退；`--required` 用于必须携带加速库的打包门禁。日常 `run/check` 只检测现有库，**不编译**。Windows 玩家收到已打包的游戏目录，无需 Python 或 C 编译器。其他架构、双精度引擎使用严格回退。

导出仍使用 `export_presets.cfg` 的 `Windows Desktop` 预设；已启用的导航导出插件在编辑器 GUI / CLI 导出时自动将可用的目标库放在可执行文件旁。清单使用官方 `windows.x86_64` / `linux.x86_64` 平台键；没有目标库也能正常导出，日志为 `BH_NAVIGATION_EXPORT fallback:`。分发整个目录（`.exe`、`.pck` 及存在的 `route_kernel.dll`），不要只拷贝 exe。

```bash
# --templates 指向官方 4.7.2 模板目录（包含 version.txt），复制到隔离配置后导出
python3 tools/godot.py export --godot <Godot> --templates <模板目录> --output .local/exports/windows/blue-hour.exe
# 已在编辑器安装模板时也可正常从编辑器导出
```

Linux 对照导出可使用 `--preset "Linux Desktop"` 与 `.x86_64` 输出路径。

首次编辑器打开不会编译或等待 helper；只在游戏启动时尝试一次加载。加载失败后保持严格回退，本次进程不重试。修复/补齐库后重新启动游戏。原生库只支持可信的本地构建产物；Godot 加载损坏库可能输出引擎诊断，但游戏仍继续完整校验。Windows 构建、Wine 或导出测试均不能替代原生 Windows 实机性能验收。

只有一个入口，无需任何玩法参数。存档位于 `user://playable-v1/run.enemy-v1.json`。

操作：左键地面移动、点建筑派工/再点取消；WASD 移动镜头，滚轮缩放，空格暂停，Esc 暂停菜单。发动巴士后需全员到达才能归航。

## 测试

```bash
python tools/godot.py check --godot <Godot 可执行文件>   # 导入 + 启动 + 单元/契约测试 + 完整一局冒烟（tests/smoke_loop.gd）
```

所有输出写在被忽略的 `.local/` 下，不会碰真实玩家存档。

## 文档

- [AGENTS.md](AGENTS.md)：协作与代码约定
- [docs/architecture.md](docs/architecture.md)：当前架构与模块

历史里程碑文档、验收记录和截图已从仓库移除，需要时查看 git 历史。

美术为项目原创（含 AI 辅助生成、SVG 与代码绘制），音效为数学合成；逐文件来源与 SHA 见 `assets/PROVENANCE.json`。本仓库暂无 LICENSE，公开可见不代表授予复制、分发或商用许可。
