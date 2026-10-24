# ISL 契约到模板渲染：复审可运行案例

从生成源码、业务数据到渲染输出连续执行，提供本次合并申报的实际集成证据。
适用范围和拒绝条件见 [兼容性说明](../docs/COMPATIBILITY.md)。

## 复现

需要 Python 3、Git 和支持 moon.work 的 MoonBit 工具链；使用的工具链版本会写入结果。
在同一父目录准备三个仓库。stencil-contract 使用本次修订版本，其余两个固定如下：

```sh
git clone https://github.com/LL124-Arch/stencil-contract.git
git clone https://github.com/LL124-Arch/ion-schema-codegen.git
git -C ion-schema-codegen checkout 558dc610cdbb559a1e46d4ee285a702b72dfc65b
git clone https://github.com/LL124-Arch/ion-patch.git
git -C ion-patch checkout f956351ddbed8aa87b0895b68246b2c2308f80cb
cd stencil-contract
moon update
cd integration
moon update
python verify.py
```

`moon.work` 使用相对路径连接三个真实模块；没有复制补丁库实现，也不要求
ion-patch 和本次 stencil-contract 版本已经发布到 Mooncakes。
程序仅修改预期的生成文件并比对其格式化后 SHA-256；CLI 负例在临时目录中运行。

期望的实际运行结果：

```json
{"status":"passed","output":"Order 42: MoonBit x3","inverse_restored":true}
```

这段输出只有在程序完成补丁应用、ISL 再验证、投影、契约检查、渲染及逆补丁核对后产生。
机器核验记录见 [verification.json](verification.json)，失败时脚本以非零退出。

## 案例文件与行为

| 文件 | 用途 |
| --- | --- |
| common.isl / order.isl | 约束在单独 Schema 定义，通过相对路径及 as 别名引用 |
| generated.mbt | 由固定版本 CLI 生成，实际编译并调用 |
| pipeline.mbt | 统一的 `render_order` 检查终点，以及补丁/逆补丁流程 |
| projection.mbt | 原 Ion 数据到 JSON 的拒绝式投影；不支持的语义显式失败 |
| pipeline_test.mbt | 四目标验证合法值、错误导入约束、投影拒绝及坏补丁不能绕过校验 |
| verify.py | 重生成一致性、四目标检查、CLI 错误、来源与结果记录 |

`verify.py` 还验证五类文件输入失败：缺文件、未知选定类型、循环文件导入、
只导入中间文件时引用其依赖类型、不支持的约束。每次错误均核对输出文件没有被覆盖。

本例不是全量 ISL 校验器或通用 Schema 翻译器。投影只接受无注解的 JSON 兼容 Ion 域，
整数进入模板时限制在 ±(2^53−1)；其余精度、重复字段、typed null 等语义不会静默丢弃。
