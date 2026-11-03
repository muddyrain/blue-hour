# P0-RECORD-HASH-01：精确收据传输候选

风险为 PERSISTENCE/HIGH_RISK。本轮在 macOS 的公开源码克隆上，从 `541a4c9cb25330120828f6d2f92cbbbbc88c3508` 继续；它不是附件所述 Windows 内部工作区。普通入口、存档 schema、玩法参数和素材不变。完整生产门禁保持 BLOCKED。

## 根因与边界

Godot 4.7.2 的 `JSON.stringify(..., full_precision=true)` 与 `JSON.parse_string` 对已知约 `9.7e-17` 值产生相邻 binary64 值的二周期。历史 `TransactionReceipt.fingerprint` 和 `SurvivalContracts.fingerprint` 都先 stringify/parse 再 stringify；`ReceiptJournal.append` 又 stringify 整个 `{payload, sha256}`。哈希计算与实际回读看到不同的值，产生 `RECORD_READBACK:RECORD_HASH`。

新克隆上先运行未修改的 `tests/known_hash_cycle.gd`，退出 1、`MINIMAL_HASH_CYCLE=true`；再用合法 CAMP_REGISTERED → STARTED 链将相同值放入 rules，实际 append 同样拒绝。前者是最小纯因果，后者证实真实磁盘路径。真实战场 S1 另外验收，不把 rules 夹具当自然任务过程。

## 新记录格式

新日志外层严格为三个字段：`record_encoding="BH_EXACT_JSON_V1"`、`payload`、`sha256`。payload 是显式带标签的值树，不再将业务数值交给 JSON 数值编解码。

| 业务值 | 编码 |
| --- | --- |
| null / bool / String、StringName | 对应标签及值；StringName 转字符串 |
| int / float | `number` 标签及 binary64 小端 8 字节的 16 位小写 hex |
| Array | `array` 标签及依次编码的元素 |
| Dictionary | `object` 标签及按字符串键排序的键值对 |

指纹为 `SHA256("BH_EXACT_JSON_V1\n" + compact_JSON(encoded_tree))`。编码后的 JSON 只有数组、字符串、bool，不含任何浮点。解码只接受已知标签、正确长度、规范 hex、有限数值、严格排序且唯一的键，保持原 JSON 深度上限。不会执行对象反序列化。

JSON 业务域原先将 int 2 与 float 2.0 视为同值；安全范围内整数精确转为 double。正负零同值，近零正负、最小 subnormal、相邻非零 binary64 和相邻生命值仍逐位不同。不截小数、不设容差、不收敛循环、不重算已存收据。

`TransactionReceipt.fingerprint` 现在是新记录指纹。旧算法移到显式 `legacy_fingerprint`。`TransactionReceipt.same` 保留历史业务 equality，避免暗改旧转换/重试合同；它不是新记录的完整性校验器。`SurvivalContracts.fingerprint` 仍为历史业务算法，因其输出已用于世界、营地、结果、训练、token、迁移身份和资源兼容性；本轮不迁移这些嵌入哈希。精确收据传输保持其输入逐位相同，解决此路径的回读漂移；任意外部普通 JSON 往返仍不能宣称可靠。

## 旧记录与调用路径

旧外层必须恰为 `{payload:Dictionary, sha256:String}`，只按历史算法验证。带编码版本者只按该版本验证，未知版本、缺字段、附加字段、编码错误或哈希错误均拒绝，不回落另一算法。旧有效收据保持原字节和原 digest；旧坏收据，包括原浮点二周期导致的失败 stage，不会因新算法被接受。

`ReceiptJournal.read_all` 逐条解码后仍运行完整 `TransactionReceipt.problem/transition`，混合新旧链的 `previous_hash` 指向前一条真实 digest。代次、阶段、冻结输入、死亡与名册验证不变。新写入只有新格式；不覆写旧 generation。

`RunTransaction` 的 binding_version=1 仍按旧算法读写；该封装只含字符串和整数代次。领取 ACK 重试的 `_claim_retry_hash` 使用新记录指纹；暂存容量预检使用新编码后的真实字节数。既有目录限制、大小/完成余量、文件回读、stage 发布、锁及 ACK 顺序保持。

测试控制器从 journal 的认证读取入口取得 payload，避免绕过新编码。恢复对照另存 `snapshot.exact.json`，原普通 JSON 截面仍可作诊断，不能用它证明逐位恢复。macOS 启动器对子进程设置隔离的用户 home，使原用户目录保护条件实际生效。

## 验证与仍需补齐的门禁

公开复测：`python3 tools/godot.py check --godot /path/to/pinned/Godot`。新增 `tests/record_hash.gd` 覆盖精确往返、边界与负例、实际写盘、旧有效记录及旧坏记录；`tests/record_hash_process.gd` 为隔离任务目录提供跨 PID、同内容代次、ACK 重试及写者争用驱动。原生流程使用原有控制器，新增 `--verify-record-hash` 仅为当前隔离任务复用营地驱动。

本机测试结果、失败重试、引擎/包/输入 SHA 和进程身份记录在私有审阅包。同一最终PCK已在macOS完成原极小浮点帧位暂存、跨PID/同内容代次/ACK重试、暂存及完整结果发布后的真实强杀、训练READY强杀、真实救援和近敌夹具阵亡、后续营地训练及四活五历史恢复。另在schema102全新旅程自然完成正常口粮→饥饿死亡→新PID终态字节保留；这不等于全部111饥饿组合已验。

源码、macOS原生窗口、macOS引擎加载导出PCK、Windows EXE分别标注，不互相升级。Windows原生执行、Windows独占文件锁/强杀矩阵、未提供的内部历史档和剩余组合仍缺证据；结论PARTIAL / NO-GO-PRODUCTION，不签GO-RECORD-HASH。跨PID单写者争用和主备拒绝的macOS结果不能升级为Windows文件共享锁通过。

新格式不被旧可执行文件理解，故不可用旧包继续本轮新写入的日志。未知或旧武器规则途中档仍由原保护边界拒绝。本轮不自动切换普通正式生存默认，也不声称任意崩溃均可恢复。
