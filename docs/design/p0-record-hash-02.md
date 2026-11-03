# 精确收据传输

收据在写盘前已经参与业务指纹计算，随后普通 JSON 数值编码又改变了一个约 9.7e-17 的 binary64 时钟值，导致 stage 回读被 RECORD_READBACK:RECORD_HASH 拒绝。本次只改变收据的存储外层，避免再次转换业务数值；不是改变时钟、增加容差或改写世界数据。

## 编码与认证

新记录外层严格包含 record_encoding、payload、sha256 三个字段，版本为 BH_EXACT_JSON_V1。payload 是带 null/bool/string/number/array/object 标签的值树；number 用 8 字节 little-endian binary64 的 16 位小写 hex，两个零统一为正零。安全整数与等值浮点保持既有业务等值规则，非零相邻数保持区别；有限浮点域沿既有合同，整数输入不得超过安全整数范围。

对象键排序且唯一，数组保持顺序。摘要为版本、换行和紧凑规范值树 JSON 的 SHA256。解码拒绝非有限数、负零非规范表示、大小写错误的 hex、未知标签、重复或乱序键、过深结构、缺失或额外字段及坏摘要。收据业务校验继续在解码之后执行。

未标版本记录仅用历史算法认证；显式新版本仅用指定算法，认证失败没有另一算法兜底。旧有效记录不改字节、不重算摘要，追加的新记录仍引用旧 previous_hash。旧可执行包不能读取新记录；不得用唯一玩家档试验降级。

## 保留的业务边界

TransactionReceipt.fingerprint 用于新收据完整性；TransactionReceipt.same、SurvivalContracts.fingerprint 和 binding_version=1 保留历史业务算法。世界、规则、token、训练、迁移及资源兼容指纹没有整体迁移。目录、stage、容量、实际编码字节预检、回读后发布、单写者及 READY/ACK 顺序保持。

普通与 111 入口、业务 schema、玩法数值、美术、导航和碰撞不变。新的包内诊断路由只有明确参数才启用，数据必须位于本轮隔离目录。原引擎普通 JSON 二周期仍由 known_hash_cycle 保留；该检查现在同时要求精确编码十次真实文件往返成功，不能仅看退出码。

## 可复测范围

公开 check 增加编码、混合链、容量和畸形记录回归，并保留原动作 505、稳定性 17、感染者 V1 172 项。Windows 编排入口为 tools/record_hash_matrix.py，使用独立合成 profile、可观察 PID 屏障、真实进程强杀和真实独占文件句柄；原生渲染使用不切换的独立 Windows 桌面，不注入系统键鼠。每个 case 保存参数、PID、前后 SHA、断言与失败原件；SCRIPT ERROR、先前断言失败或超时均不得计通过。

完整旧研究档不是公开夹具，缺少的真实历史原件列 NOT_PROVIDED。软件层通过不代表物理输入、显示流畅性、任意断电或生产发布已签核。最终本轮结果见 [验证边界](../VALIDATION.md)，正式生产门禁保持 BLOCKED，等待审阅。
