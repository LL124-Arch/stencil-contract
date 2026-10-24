# 复审核查：契约终点、整数语义与 Schema 导入保义范围

本说明对应 2026-10-24 的复审修订。主入口仓库为 stencil-contract；
ISL 生成器固定到 `ion-schema-codegen@558dc61`，补丁库固定到
`ion-patch@f956351`。具体复现来源与命令见 [集成案例](../integration/README.md)。

## 1. 驳回意见对应的实际问题与修正

| 意见 | 核查事实 | 交付修改 | 可执行证据 |
| --- | --- | --- | --- |
| 合并申报未建立 ISL 2.0 契约语义终点 | 原申报书只有三个独立库的功能，未连通 Ion 与 JSON | `render_order` 统一执行生成解码、投影、契约检查与渲染；补丁结果必须再次解码 | `integration/pipeline.mbt`、四目标 `pipeline_test.mbt` |
| 整数约束不明确 | 原 importer 把 `integer` 映射为 `Number`，1.5 也可能通过 | 新增 `ContractKind::Integer`；文本入口保留数字原文，精确处理小数、指数、边界和倍数 | `compatibility_test.mbt`；大于 2^53 的相邻整数与高精度小数回归 |
| Schema 导入保义范围不明确 | 隐式容器类型推断会缩窄合法实例；方言及路径表示边界未定义 | 明确 2020-12 保义子集；拒绝无法表示的属性名、隐式嵌套结构、外部/递归引用及引用旁验证关键字 | importer 负向测试、五项真实 CLI 负例 |

这次交付建立的是**受支持 ISL 子集的完整执行链**。全量 ISL 2.0 的实现仍未完成；
下表区分已执行的能力、受限能力与明确拒绝项。没有把支持子集改写成全标准兼容。

## 2. ISL → 生成代码 → 渲染的终点

```text
common.isl 的整数/长度约束
  → order.isl 相对导入和 as 别名
  → Native CLI 解析/改名/生成 → 编译 generated.mbt
  → Ion 原值通过 Order::from_ion
  → ion-patch diff / apply_checked
  → 补丁结果再次通过 Order::from_ion
  → project_for_template 对原 Ion 值执行拒绝式投影
  → JSON Schema 数据检查 + 模板引用检查
  → 报告无 error 后 Stencil 渲染
```

`check_schema` 检查 Schema 本身；生成文件成功也不能代替实际数据校验。
本案例把编译后的 `Order::from_ion` 放在渲染入口和补丁之后。
`to_ion` 是序列化函数，不作为校验器使用。补丁库只保证自己的编辑语义，
不会自动保证结果符合 ISL；负例验证补丁后 quantity=0 时仍不能渲染。

本例的 JSON Schema 是针对 Order 手工声明并通过案例核对的模板侧契约，
不是通用 ISL→JSON Schema 翻译器。ISL 解码器始终是上游契约的权威检查。

| 本例 ISL 声明 | 生成/校验语义 | 模板侧对应 |
| --- | --- | --- |
| `SafeId: int, valid_values: range::[0, 9007199254740991]` | BigInt，不截断为 Int/Double | Integer，区间相同 |
| 导入 `PositiveQuantity as Quantity`，范围 [1,100] | 导入原约束仍执行 | Integer，范围 [1,100] |
| `Title: string, codepoint_length: range::[1,80]` | 按 Unicode 码点计数 | String，minLength/maxLength 相同 |
| closed fields，三个 required 字段 | 缺项、额外项、错误 Ion kind 均拒绝 | required + additionalProperties=false |

`tag::1` 可以满足某些 ISL int 约束；这不代表注解可以保留到 JSON。
案例投影的是原 Ion 值，而非已经投影为原生字段的业务模型，因而注解仍可被检测和拒绝。

### 已执行的正反例

下表对应 `pipeline_test.mbt` 与 `compatibility_test.mbt` 中的实际断言，
不是示意性的预期结果。

| 输入/操作 | 实测行为 |
| --- | --- |
| Order 数量从 2 补丁为 3 | 输出 `Order 42: MoonBit x3`；逆补丁恢复原文档 |
| Order 的 quantity 为 0、101、2.5 或 null.int | `isl` 阶段拒绝，未进入渲染 |
| 补丁把合法 quantity 改为 0 | 再验证在 quantity 路径失败；撤销后可渲染数量 2 |
| Order 的 quantity 为 tag::1 | ISL int 接受该值；投影在 `/quantity` 拒绝注解 |
| 投影 `{n:1,n:2}` / `{n:null.int}` | 在 `/n` 拒绝重复字段 / typed null |
| JSON integer 为 1.0、1e3 / 1.0000000000000000000001 | 前两者通过，后者在 `/n` 报 Integer 类型错误 |
| JSON maximum=9007199254740992，输入 9007199254740993 | 精确判定越界，不受 Double 舍入影响 |
| 本地 `$ref` 引用正整数数组，输入 [1,1.5] / uniqueItems 输入 [1,1.0] | 分别因 Integer / 数值相等的重复元素失败 |

## 3. Ion→JSON 的保义域

| 输入 | 行为 | 保障 |
| --- | --- | --- |
| 无注解 bool、string、plain null | 直接映射 | 类型和值不变 |
| int，绝对值 ≤ 9007199254740991 | 以原十进制数字创建 JSON | 模板所用 Double 也能精确表示该整数 |
| list | 按输入顺序递归投影 | 下标顺序不变 |
| struct，字段名均有文本且不重复 | 递归投影成 JSON object | 键和值保留；不承诺对象字段排列 |
| 任意层注解、typed null、重复字段、无文本 SID | 拒绝，返回阶段和 JSON Pointer | 不去注解、不覆盖同名字段、不把 typed null 当 plain null |
| 超出上述安全整数范围、decimal、float、symbol、timestamp、LOB、sexp | 拒绝 | 不经过截断、舍入、字符串化或改 kind 后继续 |

上表是 `project_for_template` 的边界。它是合并示例的适配层，不是通用 Ion 编码器。
ISL int 本身仍为任意精度；该安全整数限制只属于进入模板的投影域。
JSON 契约文本入口能检查更大的精确整数，不能因此推导模板数值渲染也支持同样范围。

## 4. JSON Schema 导入的保义配置

### 文本入口：`ContractSchema::from_json_schema_text`

适用域：对象根样例，方言缺省为本配置的 2020-12 子集；若给出 `$schema`，
必须为 `https://json-schema.org/draft/2020-12/schema`。样例文本用
`parse_contract_json` 读取，避免数字在进入检查器之前已被舍入。

在该域内，导入后报告的数据错误对应被支持的 Schema 断言；模板错误另行报告，
未使用字段仅为 warning。保留的断言如下：

| 项目 | 范围与对应规则 |
| --- | --- |
| `type` | 单个 object/array/string/boolean/null/number/integer；Integer 按数学整数判断，1.0 与 1e3 通过，1.5 不通过 |
| 对象 | properties、required、布尔 additionalProperties；缺省允许额外键；嵌套容器必须显式给 type |
| 数组 | 单一 items Schema；逐项递归；minItems/maxItems；uniqueItems 使用精确数值相等 |
| 标量与对象断言 | enum、const、四种数值上下界、正 multipleOf、字符串码点长度、对象属性数量 |
| 键名与依赖 | propertyNames 的布尔/类型/enum/const/长度子集；dependentRequired 按触发键是否存在执行 |
| 引用 | 本文档的无环 `#`/`#/...` JSON Pointer；解码 ~0/~1；每个使用点都执行目标约束，数组 items 同样适用 |
| 数字 | 保留原 token；BigInt 交叉缩放比较、整除和相等；不按 Double 的舍入结果判断 |

显式拒绝：外部/递归 `$ref`、引用旁的验证关键字、嵌套 `$id` 资源作用域、
type union、tuple items、组合/条件关键字、Schema 形式 additionalProperties、
无法平铺的空属性名或含 `.` / `[` / `]` 的属性名，以及其他未列明验证关键字。
`$defs` / `definitions` 可供本地引用；该 importer 不是全量 metaschema 校验器。

数值 token 最长 4096 字符、指数绝对值最多 4096，文本最大嵌套 128 层；
超界或重复 JSON 键返回错误。数值表示已被其他解析器舍弃时不能恢复原文，
所以精确文本契约必须使用上述两个文本入口。

### 原有 Json 入口：`ContractSchema::from_json_schema(Json)`

该入口也已修复 Integer、精确数值运算、方言/路径/引用边界，但只针对传入 Json
实际保存的数值表示；不能恢复调用前发生的舍入。它还保留原有扩展：
MoonBit Regex 的 pattern，以及强制断言 date/time/date-time/uuid 的 format。
这些扩展有单独测试，但不在跨引擎、默认 JSON Schema format 注解语义的保义承诺内。
为避免混淆，文本保义入口直接拒绝 pattern/format。

## 5. ISL 2.0 兼容范围

这里描述固定生成器版本的支持面，不表示 stencil-contract 本身接受 ISL。
细节以该版本的 [生成器支持范围](https://github.com/LL124-Arch/ion-schema-codegen/blob/558dc610cdbb559a1e46d4ee285a702b72dfc65b/README.md#支持范围)
与 [Schema 实现](https://github.com/LL124-Arch/ion-schema-codegen/tree/558dc610cdbb559a1e46d4ee285a702b72dfc65b) 为准；下表是范围摘要。

| ISL 能力 | 当前边界 |
| --- | --- |
| 基本类型/字段/list | 已列明标量、open/closed struct、required/optional/重复 occurs、列表及命名类型；unsupported 形式报错 |
| any / $any / nullable | 按既有类型模型保存原 Ion 值；plain/typed null 规则区分；不自动等价于 JSON null |
| valid_values | 有限值集合；数值和 timestamp 范围及开闭端点；非所有 Ion kind 的任意范围 |
| 长度/元素 | 已列明 container/codepoint/utf8/LOB 长度、element/distinct、field_names、contains、ordered_elements |
| decimal / timestamp / float | 已支持 precision/exponent、timestamp precision/offset、ieee754；上游 Float 为 32 位，不能恢复 binary64 已丢失精度 |
| 逻辑类型 | all_of/any_of/one_of/not 及已实现 inline/nullable/import 参数组合 |
| annotations / regex | 已实现的简化和标准注解子集、正则子集；不等于任意标准表达式/所有正则语法 |
| 递归 | 已支持能安全表示、有终止边的结构；纯递归 alias、无基例及同值自调用循环拒绝 |
| document | 顶层值流；不能嵌入单个字段或列表值 |
| imports | Native CLI 相对本地文件；整份/选定类型/as 与已支持 inline import；不解析网络或循环导入 |
| 保义边界 | 在定义所属文件解析本地及直接导入名；保留目标类型的受支持约束；不把传递导入自动暴露给根文件 |
| 全量 ISL | 未实现；未列明的语法和 open-content 形式按生成器支持矩阵明确失败 |

ISL 导入保障由两层证据组成：编译后的真实约束正反例，以及 CLI 对缺失文件、
未知类型、循环导入、传递可见性与不支持约束的非零退出。失败时原输出文件保持不变。

## 6. 复现与依据

运行 [integration/verify.py](../integration/verify.py) 可重跑库检查、四目标测试、
ISL 重生成一致性、真实渲染和 CLI 负例；结果保存在
[integration/verification.json](../integration/verification.json)。
复现基线固定 compiler/core `0.10.14+7d59c7ec9`，moon `0.1.20260920`；
不把此基线上的通过结果表述为对未来工具链版本的无条件兼容。

规范依据：[Ion Schema 2.0](https://amazon-ion.github.io/ion-schema/docs/isl-2-0/spec)、
[JSON Schema 2020-12 Validation](https://json-schema.org/draft/2020-12/json-schema-validation)。
实现证据：[整数与精确比较](../contract_number.mbt)、[文本入口](../contract_json.mbt)、
[Schema 导入器](../contract_interop.mbt)、[数值与导入回归](../compatibility_test.mbt)。
